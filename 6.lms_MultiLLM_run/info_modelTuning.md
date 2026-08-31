# 모델 튜닝 — 로컬 LLM + Claude Code 를 실사용 가능하게

로컬 LLM 백엔드에서 Claude Code 를 쓸 때 손대는 축은 **두 개**다.

| 축 | 무엇 | 문서 |
| :--- | :--- | :--- |
| **요청 축소 (다이어트)** | claude 가 보내는 프롬프트(도구 스키마)를 줄임 — 20k→3k | [`info_promptDiet.md`](info_promptDiet.md) |
| **서버 튜닝 (이 문서)** | LMS 로드 파라미터로 VRAM·속도·컨텍스트를 맞춤 | 여기 |

둘은 독립이고 곱해진다. 다이어트로 **왕복당 prefill** 을 줄이고, 튜닝으로 **처리 속도·최대 길이**를 정한다.

> 실측 출처: fg1 (NVIDIA 16GB) + LM Studio + Claude Code. 상세 수치는
> `DeviceManagement/fg1/lms/context_128k_report.md`, `benchmark_lms_report.md`.

---

## 1. 튜닝 노브 (이 스택의 위치)

이 스택은 `entrypoint.lms.sh` 가 `lms load` 로 모델을 올린다. 노브는 전부 **`.env`** 에 있다.

| `.env` 변수 | 역할 | 주의 |
| :--- | :--- | :--- |
| `LMS_CONTEXT_LENGTH` | 컨텍스트 토큰 상한 | Claude Code 는 시스템+도구가 커서 **32768 이상** 필요(기본 8192 부족) |
| `LMS_GPU` | GPU offload 비율 (`max`/`off`/`0~1`) | VRAM<모델 환경에서 `max` 는 **CUDA OOM** — §3 |
| `LMS_PARALLEL` | 동시 예측 슬롯 | llmster 는 ctx 를 슬롯 수로 **분할**(4면 32k→8k). **반드시 1** (아니면 500) |
| `CLAUDE_MAX_OUTPUT_TOKENS` | 출력 상한 | 32k ctx 에 input+output 합산이 들어가야 함 |

`lms load` 에는 **KV 양자화 플래그가 없다**(§4-B). 위 4개가 이 스택에서 조절 가능한 전부다.

### CUDA 런타임 자동선택 함정 (이미 반영됨)

llmster 는 CUDA 백엔드를 설치해도 기본 SELECTED 가 **CPU(avx2)** 인 경우가 있다. 그러면
`LMS_GPU=max` 여도 CPU 로 추론해 대형 모델이 극도로 느려지고 504 가 난다. `entrypoint.lms.sh`
3.5절이 부팅 시 `lms runtime select <nvidia-cuda>` 로 자동 교정한다 — GPU 인데 느리면 여기부터 의심.

---

## 2. VRAM 예산 — offload 안전선

**병목은 RAM 이 아니라 VRAM 안에서 가중치·KV·prefill 연산 버퍼를 어떻게 나누냐다.**

핵심 함정: **KV 캐시는 로드 시 선할당되지만, prefill 연산 버퍼(batch)는 추론 시점에 추가로 필요**하다.
그래서 VRAM 을 꽉 채우면 **로드는 성공하고 짧은 요청도 통과하지만, 긴 프롬프트에서 CUDA OOM 크래시**한다.

fg1 16GB 실측 (gemma-4-26b, KV q8_0, 128k):

| `--gpu` | 레이어 | VRAM | 짧은 프롬프트 | 긴 프롬프트(110k) |
| :--- | ---: | ---: | :--- | :--- |
| 0.75 | 23 | 97% | 25 tok/s (빠름) | ❌ CUDA OOM 크래시 |
| **0.6** | 19 | 83% | 20 tok/s | ✅ 통과 |

→ **짧은 프롬프트 속도만 보고 offload 를 올리지 말 것.** 128k 에이전트 용도의 안전선은 VRAM **~83%**.
`LMS_GPU=max` 를 쓰려면 VRAM 이 모델보다 확실히 커야 한다(그때만 안전).

---

## 3. 128k 장문 — 두 경로

| 경로 | 방법 | 이 스택 |
| :--- | :--- | :--- |
| **A. 소형 MQA 모델** | KV 헤드가 작아 128k KV 가 극소 | ✅ **기본** (`google/gemma-4-e2b`, 백엔드당 ~3.95GB) |
| **B. 대형 모델 + KV q8_0** | KV 를 절반으로 양자화 | ❌ `lms load` 불가 (아래) |

**경로 A 가 이 스택의 정답이다.** `gemma-4-e2b` 는 MQA(KV 헤드 1개)+sliding window 라 128k 풀
컨텍스트여도 KV 캐시가 작아, 16GB GPU 에 **2 백엔드**가 각각 128k 로 올라간다(README 검증: 40k needle 통과).

**경로 B 는 이 스택에서 코드 변경 없이는 불가**하다. `lms load` 에 KV 양자화 플래그가 없어
lmstudio Python SDK 를 경유해야 한다(`llama_k_cache_quantization_type=q8_0`). 대형 non-MQA 모델을
단일 16GB GPU 에서 장문으로 굴려야 할 때만 필요하며, 구현 예시는
`DeviceManagement/fg1/lms/load_model_q8.py` (+`load_model_q8.zsh`). 이 스택에 이식하려면
`entrypoint.lms.sh` 4)번의 `lms load` 를 SDK 호출로 교체 + 컨테이너에 SDK(.venv) 반입이 필요하다
— MQA 소형 모델로 충분하면 **하지 말 것**.

---

## 4. 추론 모델은 `/no_think` (Qwen3 등)

Qwen3 계열은 하이브리드 **추론 모델**이라 기본값이 "생각"을 한다. 사소한 질문에도 reasoning
토큰을 대량 소모한다. fg1 실측 (Qwen3-8B):

| 프롬프트 | reasoning 토큰 | 소요 |
| :--- | ---: | ---: |
| "1~5 출력 bash" | 431 | 27.5s |
| 같은 질문 + **`/no_think`** | 0 | **1.8s** |

수업 데모·대화형은 반응속도가 생명이니 프롬프트에 `/no_think` 를 기본으로 넣을 것. (Gemma·비추론
모델은 해당 없음.)

---

## 5. 수업용 소형 모델 선택 (8GB PC · Claude Code 동작)

윈도우 교실 PC(VRAM 8GB)에서 **Claude Code 에이전트가 실제로 도는** 작은 모델. 관문은 "tool_use
표기"가 아니라 **에이전트 루프(도구 호출→관찰→다음 호출)를 견디느냐** 다 — `devstral-small-2507`
이 바로 여기서 탈락(500)했으므로 **실측 전엔 보장 못 함**.

| 모델 | 파일(Q4) | 상태 | 비고 |
| :--- | ---: | :--- | :--- |
| **Qwen3-8B** (`qwen/qwen3-8b`) | 4.7GB | ✅ fg1 실측 통과 | API·에이전트·**실제 Bash 도구 호출** 통과. `--gpu 0.8`→VRAM 7.9GB/32k |
| Qwen2.5-Coder-7B | ~4.7GB | 미검증 | 코딩 수업 후보 |
| 4B 이하 | 2~3GB | 위험 | 단발은 되어도 멀티스텝 에이전트에서 형식 붕괴 |

**7~8B 가 에이전트 실질 하한선.** 8GB 카드는 7.9/8.0 으로 빠듯하니(디스플레이가 VRAM 을 먹음)
`--gpu 0.7` 로 낮추거나 ctx 를 16k 로 줄일 여유를 둘 것.

---

## 6. Windows VSCode Claude Code 확장 설정

> 호스트(Linux/Mac)용은 [`vscode-connect.sh`](vscode-connect.sh) / [`PATCH.md`](PATCH.md) 참조.
> **Windows 는 그 bash 스크립트가 네이티브로 안 돈다** — 아래 수동 절차 또는
> [`vscode-connect.ps1`](vscode-connect.ps1)(PowerShell 대응물) 을 쓸 것.

Claude Code 확장은 CLI 와 동일하게 **`%USERPROFILE%\.claude\settings.json`**
(= `C:\Users\<사용자>\.claude\settings.json`) 를 읽는다. 여기에 백엔드 주소·모델을 넣는다.

### 시나리오 두 가지

| | A. 각 PC 로컬 LM Studio | B. GPU 서버 게이트웨이 클라이언트 |
| :--- | :--- | :--- |
| 모델 구동 | 그 윈도우 PC 자신 | 원격 GPU 서버 |
| `ANTHROPIC_BASE_URL` | `http://localhost:1234` | `http://<서버IP>:8080` |
| 수업 적합 | 교실 PC 각자 소형 모델(§5) | PC 는 씬 클라이언트, 서버가 무거운 모델 |
| 사전 조건 | PC 에 LM Studio + 모델 로드 | 서버 `./start.sh`, 서버 방화벽 8080 개방 |

### settings.json 내용 (두 시나리오 공통 형식)

```jsonc
{
  "model": "qwen/qwen3-8b",                         // 로드한 모델 키
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:1234",  // A: localhost:1234 / B: http://<서버IP>:8080
    "ANTHROPIC_AUTH_TOKEN": "lms",                  // 더미 토큰(값 무관, 존재만 하면 됨)
    "API_TIMEOUT_MS": "600000",                     // 로컬 추론 느림 → 10분(필수)
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1" // 비-Anthropic 엔드포인트 잡음 차단
  }
}
```

### 수동 절차 (PowerShell)

```powershell
# 1) 폴더 생성 + 파일 편집
mkdir "$env:USERPROFILE\.claude" -Force
notepad "$env:USERPROFILE\.claude\settings.json"   # 위 JSON 붙여넣기 (BASE_URL 시나리오에 맞게)

# 2) VSCode 재시작: 명령팔레트(Ctrl+Shift+P) → "Developer: Reload Window"

# 3) 확인 — 백엔드가 응답하는지 (시나리오 A)
curl.exe http://localhost:1234/v1/models          # 시나리오 B 는 http://<서버IP>:8080/v1/models
```

또는 [`vscode-connect.ps1`](vscode-connect.ps1) 로 자동 병합(기존 키 보존·되돌리기 가능):

```powershell
# 시나리오 A (로컬 LM Studio)
.\vscode-connect.ps1 -Action on -BaseUrl http://localhost:1234 -Model qwen/qwen3-8b
# 시나리오 B (원격 게이트웨이)
.\vscode-connect.ps1 -Action on -BaseUrl http://192.168.0.4:8080 -Model google/gemma-4-e2b
.\vscode-connect.ps1 -Action status
.\vscode-connect.ps1 -Action off        # 우리가 넣은 키만 제거 → Anthropic 복귀
```

### Windows 함정

* **`localhost` vs 서버 IP** — 시나리오 B 는 `localhost` 가 아니라 **GPU 서버의 LAN IP**. 서버 쪽
  `start.sh` 는 게이트웨이를 `0.0.0.0:8080` 으로 노출하지만, **서버 OS 방화벽에서 8080 인바운드
  허용**이 별도로 필요하다(리눅스 `ufw allow 8080`, 클라우드면 보안그룹).
* **로컬 LM Studio 는 네트워크 바인딩 확인** — 시나리오 A 라도 확장이 다른 프로세스로 접근하면
  LM Studio 설정에서 "Serve on Local Network"(0.0.0.0 바인드)가 켜져야 할 수 있다. 같은 PC
  `localhost` 면 대개 문제 없음.
* **PowerShell 실행 정책** — `.ps1` 이 막히면 `powershell -ExecutionPolicy Bypass -File .\vscode-connect.ps1 ...`.
* **재시작 필수** — settings.json 을 바꾼 뒤 반드시 "Developer: Reload Window". 안 하면 이전 설정 유지.
* **경로 백슬래시** — `%USERPROFILE%` 는 `C:\Users\<사용자>`. WSL 안(`\\wsl$`)이 아니라 **윈도우
  네이티브 홈**이다. VSCode 를 WSL 원격으로 열었다면 그 리눅스 홈(`~/.claude`)을 봐야 하니 혼동 주의.
* **모델 미로드 시 JIT 400** — 서버가 모델을 안 올린 상태로 요청받으면 LM Studio 가 기본
  `ctx 8192/parallel 4`(슬롯당 2048)로 JIT 로드해 400 이 난다. 다이어트(3k)로도 못 넘으니
  **모델 선로드 필수**([`info_promptDiet.md`](info_promptDiet.md) §5).

---

## 관련

* [`info_promptDiet.md`](info_promptDiet.md) — 요청 축소(도구 스키마 제거)
* [`info_jinja_and_lms.md`](info_jinja_and_lms.md) — LMS jinja 템플릿 이슈
* [`vscode-connect.ps1`](vscode-connect.ps1) — Windows VSCode 연결 스크립트
* `DeviceManagement/fg1/lms/context_128k_report.md` — 128k·KV q8_0·offload 안전선 원본 실측
* `DeviceManagement/fg1/lms/load_model_q8.py` — KV q8_0 SDK 로더(경로 B 이식 시 참조)
