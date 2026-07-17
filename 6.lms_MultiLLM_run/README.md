# 6.lms_MultiLLM_run

**5.lms_MultiLLM 을 순수 `docker run` 으로 이식한 판.** docker compose 가 없거나 추가 설치가 불가한 air-gap 시스템 대상.

이 폴더 하나만 대상 시스템으로 복사하면 `./start.sh` 로 5.lms_MultiLLM 과 동일한 토폴로지(claude → nginx gateway → LMS 백엔드 풀 N개)를 기동한다.

---

## 왜 6.lms_MultiLLM_run?

| 항목 | 5.lms_MultiLLM | 6.lms_MultiLLM_run |
| :--- | :--- | :--- |
| 오케스트레이션 | `docker compose` | 순수 `docker run` (`start.sh`) |
| 대상 환경 | 온라인 · docker compose 설치됨 | air-gap · compose 없음 · 추가 설치 불가 |
| 이미지 | 로컬 `build` 로 준비 | 사전 `docker load -i *.tar` 로 반입 |
| 백엔드 스케일 | `--scale lms=N` | `LMS_BACKEND_COUNT=N` (lms-1 … lms-N) |
| nginx 백엔드 분산 | Docker DNS RR (compose 서비스명) | Docker DNS RR (`--network-alias lms`) |
| entrypoint 배포 | Dockerfile `COPY` 로 이미지에 굽힘 | 폴더의 스크립트를 `:ro` bind mount + `--entrypoint` 로 런타임 주입 |

## 왜 entrypoint 스크립트를 폴더에서 주입하는가

대상 air-gap 시스템의 `lms:latest` 는 **4.lms_OneLLM 판 Dockerfile 로 만들어진 이미지** 로 반입됨. 안에 구운 `entrypoint.lms.sh` 는 4 버전. 5.lms_MultiLLM 이 요구하는 게이트웨이 토폴로지 로직(claude 의 `GW_HOST/GW_PORT`)과 어긋날 수 있어, 스크립트 두 개를 이 폴더에 원본 그대로 두고 **컨테이너 기동 시 `-v ...:ro` + `--entrypoint`** 로 override 한다. 이미지 재빌드 없이 스크립트만 바꿔도 반영되는 이점도 있다.

* `entrypoint.lms.sh` — LMS 백엔드 PID1 (`lms daemon up` → `server start` → `/v1/models` 폴링 → 모델 로드 → `lms log stream`). 4·5 판이 실질적으로 동일하지만 안전 override.
* `entrypoint.sh` — claude 클라이언트 PID1. **여기가 실제로 4·5 판이 다른 부분** — 5 판은 `GW_HOST/GW_PORT` 로 게이트웨이에 직결.

---

## 폴더 구성

```
6.lms_MultiLLM_run/
├── start.sh              # 메인 기동 스크립트 (docker run 오케스트레이션)
├── entrypoint.lms.sh     # LMS 백엔드 PID1 (런타임 주입, CUDA 자동선택+LMS_PARALLEL 패치 포함)
├── entrypoint.sh         # claude 클라이언트 PID1 (5.판, 런타임 주입)
├── nginx.conf.template   # nginx 설정 템플릿 (:ro 마운트, ${LMS_PORT} envsubst)
├── .env                  # 검증 완료 working 설정 (그대로 사용 권장)
├── .env.org              # 파라미터 템플릿 (주석 상세)
├── lms-gateway.tar       # lms-gateway:latest — nginx 1.30.3 (~209MB)
├── claude.tar            # claude:latest — Claude Code CLI (~720MB)
├── SHA256SUMS            # tar 무결성 검증 (sha256sum -c SHA256SUMS)
├── vscode-connect.sh     # (Linux/mac) 호스트 VSCode 확장 → 게이트웨이 연결/해제 패치
├── vscode-connect.ps1    # (Windows) 위의 PowerShell 판 (-BaseUrl/-Model 인자)
├── lms-jinja-fix.sh      # Jinja 템플릿 오류 진단·우회 패치
├── PATCH.md              # 위 패치 2종 사용법
├── info_jinja_and_lms.md # jinja/GPU 문제 진단 기록
├── Dockerfile.small      # lms:small — 저VRAM 멀티 백엔드 테스트용 경량 이미지 (아래 절 참조)
├── build.small.sh        # lms:small 빌드 스크립트 (build.small/models/ 에 gguf 필요)
├── TEST.md               # 멀티 백엔드 검증 절차 (분산·판별·40k needle·claude 종단)
└── README.md
```

> tar·SHA256SUMS 는 git 미추적 (매체 복사로만 전달). **air-gap 반입 시 이 폴더 전체를 복사**하면 외부 의존 없음 — 단, `lms:latest` 이미지(24.7GB)는 **기반입 완료 전제** (아래 사전 조건 2 참조).

---

## 사전 조건 (대상 air-gap 시스템)

1. **docker 엔진** 설치되어 있어야 함 (`docker` CLI 사용 가능). GPU 사용 시 **NVIDIA 드라이버 + `nvidia-container-toolkit`** 필요 (`--gpus all` 전제).
2. **LMS 백엔드 이미지 (`lms:latest`) — 기반입 완료 전제.** air-gap 호스트에 이미 로드돼 있어야 한다 (gemma-4-31b-qat 18GB GGUF + CUDA 런타임 내장, ~24.7GB). 이 폴더에는 포함하지 않는다. 확인:
   ```bash
   docker image inspect lms:latest >/dev/null && echo OK
   ```
3. **나머지 이미지 반입** — **tar 2종이 이 폴더에 내장** (git 미추적, 매체 복사로만 전달):

   | tar | 이미지 (load 결과) | 크기 | 내용 |
   | :--- | :--- | :--- | :--- |
   | `lms-gateway.tar` | `lms-gateway:latest` (+`:nginx-1.30.3`) | ~209MB | nginx **1.30.3** (2026-06 보안 픽스 포함, 2026-07-15 업그레이드본) |
   | `claude.tar` | `claude:latest` | ~720MB | Claude Code CLI v2.1.195 + Node 22 |

   ```bash
   # (air-gap 호스트에서, 이 폴더 안)
   sha256sum -c SHA256SUMS        # 매체 손상 검증 (반입 직후)
   docker load -i lms-gateway.tar
   docker load -i claude.tar
   ```
   `.env` 의 `GATEWAY_IMAGE=lms-gateway:latest` 가 이미 맞춰져 있음. 태그가 다르면 `LMS_IMAGE=`/`GATEWAY_IMAGE=`/`CLAUDE_IMAGE=` 오버라이드.

4. **모델 파일 — 별도 반입 불필요.** 기반입 `lms:latest` 이미지에 `google/gemma-4-31b-qat` 내장. `LMS_MODEL_MOUNT` 빈값(named volume)이어도 이미지 내장본으로 동작.

### DVD 반입

폴더 총량 ~1GB (tar 2종 + 스크립트·문서) — **DVD 1장(4.7GB)에 통째로 들어간다.** 폴더 전체를 그대로 굽고, air-gap 측에서 통째로 복사 → `sha256sum -c SHA256SUMS` 검증 후 진행.

### air-gap GPU 동작 검증 결과 (2026-07-15, 테스트 서버)

* `lms:latest` 이미지에 CUDA 엔진 **내장** 확인: `llama.cpp-linux-x86_64-nvidia-cuda-avx2-2.23.1` (다운로드 불필요 — fresh 컨테이너에서 확인).
* `entrypoint.lms.sh` 3.5절이 부팅 시 CUDA 런타임 자동 선택 → 테스트 서버(16GB GPU)에서 VRAM 15.4GB 오프로드 동작 확인.
* ⚠️ `LMS_GPU=max` 금지: VRAM(16GB) < 모델(18.85GB) 환경에서 통짜 할당 시도 → CUDA OOM. **빈값(자동)** 이 정답. VRAM 이 모델보다 큰 장비(예: A6000 48GB)는 자동으로 전량 오프로드됨.

---

## 사용법

```bash
cd 6.lms_MultiLLM_run/
cp .env.org .env
vi .env                     # LMS_MODEL, GATEWAY_PORT, LMS_BACKEND_COUNT 조정

./start.sh                  # 기본 (GPU 사용)
USE_GPU=0 ./start.sh        # CPU 강제

./start.sh --status         # 상태 확인
./start.sh --stop           # 정지 + 제거 (네트워크·볼륨 유지)

docker exec -it claude bash
cc                          # alias = claude --dangerously-skip-permissions
```

기동 확인:

```bash
curl -fsS http://127.0.0.1:8080/v1/models | jq .
docker logs -f gateway
docker logs -f lms-1
```

---

## .env 주요 파라미터

`.env.org` 는 5.lms_MultiLLM 과 동일 스키마. 추가로 6.판이 인식하는 것:

| 변수 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `LMS_BACKEND_COUNT` | `1` | **실제 기동 개수** (5 판에서는 참고용이었지만 여기선 실제 값) |
| `LMS_PARALLEL` | `1` | 동시 예측 슬롯. llmster 는 **컨텍스트를 슬롯 수로 분할**(기본 4 → 32k 가 슬롯당 8k). Claude Code 시스템 프롬프트 ~16k 초과 시 500 (`n_keep >= n_ctx`) — **반드시 1** |
| `LMS_GPU` | (빈값=자동) | `max` 는 VRAM<모델크기 환경에서 CUDA OOM — 빈값 권장 |
| `CLAUDE_MAX_OUTPUT_TOKENS` | `8192` | Claude Code 출력 상한. 32k 컨텍스트에 input+output 합산이 들어가야 함 |
| `USE_GPU` | `1` | `1` = `--gpus all`, `0` = CPU |
| `LMS_IMAGE` | `lms:latest` | 반입한 이미지 태그와 다르면 오버라이드 |
| `GATEWAY_IMAGE` | `lms-gateway:latest` | (`.env` 에 지정됨 — 폴더 tar 의 load 결과와 일치) |
| `CLAUDE_IMAGE` | `claude:latest` | 상동 |
| `MOUNT_CODE_DIR` | (빈값) | 지정 시 `$MOUNT_CODE_DIR → /home/ubuntu/code` 마운트 |

---

## 아키텍처

```
                     ┌──── docker network: lms ─────────────────────────────┐
┌──────────┐  :8080  │  ┌─────────┐    ┌──────────────────────────────────┐ │
│  claude  │ ──────► │  │ gateway │──► │ lms-1 (alias:lms)  entrypoint.lms│ │
│ (5.판    │         │  │ (nginx) │──► │ lms-2 (alias:lms)  entrypoint.lms│ │
│  entry)  │         │  └─────────┘──► │ ...                              │ │
└──────────┘         │   L7 분산        └──────────────────────────────────┘ │
                     └──────────────────────────────────────────────────────┘
   entrypoint.sh :ro 주입                       entrypoint.lms.sh :ro 주입
   (GW_HOST/GW_PORT)                            (동일 폴더의 스크립트 override)
```

- `lms-1..N` 은 모두 `--network-alias lms` 로 붙어 있어 nginx 안 `resolver 127.0.0.11` + `proxy_pass http://lms:${LMS_PORT}` 가 라운드로빈으로 분산 (5.판과 동일 원리).
- claude 는 nginx 게이트웨이 단일 주소(`http://gateway:8080`)로 직결. 변환 프록시 없음(순수 OpenAI /v1 패스스루).

---

## lms:small — 저VRAM 멀티 백엔드 테스트 이미지 (2026-07-16 실측 검증)

16GB GPU 에서 `gemma-4-31b-qat`(단독 15.4GB 점유)로는 멀티 백엔드가 불가능하므로,
**컨텍스트를 최대(128k)로 쓸 수 있는 소형 모델을 내장한 `lms:small`** 로 멀티 LLM 을 검증한다.
`FROM lms:latest` 레이어 추가 방식이라 **`lms:latest` 원본은 바이트 하나 변경되지 않는다.**

* **모델**: `google/gemma-4-e2b` (4.6B, Q4_K_M 3.2GB + mmproj 0.9GB)
  * `context_length` **131072 (128k)** — KV 헤드 1개(MQA) + sliding window 512 라 128k 풀 컨텍스트도 KV 캐시가 극소
  * 실측 VRAM: **백엔드 1개당 ~3.95GB** (128k ctx, `--gpu max`) → 16GB GPU 에 **2개 탑재 후 8.2GB 여유** (3개도 가능 추정)
* **빌드**: `./build.small.sh` (모델 gguf 는 `build.small/models/…` 에 필요 — git 미추적, 온라인 머신에서 `lms get -y google/gemma-4-e2b` 후 `docker cp` 로 준비)
* **신규 볼륨 프리팝**: 이미지에 모델이 내장돼 있어, 새 named volume 을 `/home/lms/.lmstudio/models` 에 마운트하면 docker 가 자동 복사 — air-gap 반입 후 별도 모델 복사 불필요
* **.env 전환** (현재 커밋된 `.env` 가 이 구성):
  ```bash
  LMS_IMAGE=lms:small
  LMS_MODEL=google/gemma-4-e2b
  LMS_CONTEXT_LENGTH=131072
  LMS_GPU=max              # 주의: 빈값(자동)이면 CPU 로드 되는 경우 있음 — small 은 max 고정
  LMS_BACKEND_COUNT=2
  LMS_MODEL_MOUNT=lms-models-small
  CLAUDE_MAX_OUTPUT_TOKENS=32000   # 128k ctx 라 Claude Code 기본치 그대로 허용
  ```
* **검증 결과 (2026-07-16)**: 2 백엔드 로드(각 128k ctx) → nginx 라운드로빈 분산 확인 →
  **40,046 토큰** needle 테스트 통과(11.7s prefill, 정확 회수) → claude 컨테이너 `claude -p` 응답 정상.
* 31b 구성으로 복귀: `6.lms_MultiLLM_run_backup/.env` 를 복사 후 `./start.sh` (또는 git 이력의 .env).

---

## 5.판 대비 제약

* **동시 모델 다운로드 경합**: `LMS_MODEL_MOUNT` 을 named volume 으로 두면 모든 백엔드가 같은 볼륨을 공유. 최초 1회는 `LMS_BACKEND_COUNT=1` 로 시작해 모델을 채운 뒤 늘리기 권장.
* **healthcheck**: docker HEALTHCHECK 대신 `start.sh` 안의 능동 폴링으로 대체. 컨테이너 스스로는 healthy 상태 라벨을 갖지 않음.
* **`--restart unless-stopped`** 는 부여했지만, 부팅 후 자동 기동은 컨테이너 재시작 정책만으로 충분한지 확인 (systemd 등록이 필요할 수 있음).

---

## Multi-GPU 검토 (미실측 — 테스트 서버 GPU 1장)

`LMS_BACKEND_COUNT=N` 증설 시 GPU 배치 시나리오. **실측 검증은 못 했음** (테스트 서버 16GB GPU 1장) — air-gap 장비에서 아래 순서로 확인할 것.

| 시나리오 | 방법 | 비고 |
| :--- | :--- | :--- |
| GPU 1장 + 백엔드 1개 (기본) | 현행 `.env` 그대로 | 검증 완료 상태 |
| GPU 1장 + 백엔드 N개 | VRAM 이 (모델+KV)×N 이상일 때만 | 16GB 급에선 불가 (백엔드당 ~20GB) |
| GPU N장 + 백엔드 N개 (1:1 핀) | `start.sh` 의 `GPU_OPT=(--gpus all)` 을 백엔드 인덱스 `i` 기준 `GPU_OPT=(--gpus "\"device=$((i-1))\"")` 로 분기 | 권장 구조. nginx 라운드로빈이 요청을 백엔드(=GPU)별로 분산 |

1:1 핀 수정 위치는 `start.sh` 의 `3) LMS 백엔드 N개 기동` 루프. 각 백엔드가 자기 GPU 에 모델을 따로 올리므로 **RAM 요구도 백엔드 수에 비례**함(모델 로드 시 스테이징) — 로드는 순차로 진행됨.

검증 절차 (air-gap 장비에서):
```bash
LMS_BACKEND_COUNT=2 ./start.sh          # (1:1 핀 수정 후)
docker exec lms-1 lms ps                 # 백엔드별 로드 확인
docker exec lms-2 lms ps
nvidia-smi                               # GPU 별 VRAM 분산 확인
for i in 1 2 3 4; do curl -sS -X POST http://127.0.0.1:8080/v1/messages \
  -H 'Content-Type: application/json' -H 'x-api-key: lms' -H 'anthropic-version: 2023-06-01' \
  -d '{"model":"google/gemma-4-31b-qat","max_tokens":16,"messages":[{"role":"user","content":"hi"}]}' & done; wait
                                         # 동시 4요청 → 라운드로빈 분산 확인
```

---

## 호스트 VSCode Claude Code 확장으로 접속

컨테이너 내부 `cc` 대신, **호스트에서 실행하는 VSCode 의 Claude Code 확장**을 이 스택의
게이트웨이에 붙일 수 있다. 확장은 CLI 와 동일하게 `settings.json`(전역: Linux/mac `~/.claude/`,
Windows `%USERPROFILE%\.claude\`)을 읽으므로, 거기에 `ANTHROPIC_BASE_URL`·`ANTHROPIC_AUTH_TOKEN`·
`model` 을 넣으면 된다. 이를 자동화한 것이 OS 별 두 스크립트 — **`vscode-connect.sh`**(Linux/mac)·
**`vscode-connect.ps1`**(Windows) — 이며 둘 다 되돌리기 가능(넣은 키만 제거).

* **접속 대상 주소**: 같은 호스트면 `http://127.0.0.1:${GATEWAY_PORT}`, **다른 머신(Windows 등)에서는
  `http://<GPU호스트IP>:${GATEWAY_PORT}`**. `start.sh` 는 게이트웨이 포트를 `0.0.0.0` 으로 publish 하므로
  (`-p ${GATEWAY_PORT}:8080`) LAN 에서 바로 접근된다.
* ⚠️ **게이트웨이/LMS `/v1` 는 무인증**(토큰 `lms` 는 형식상). **신뢰 LAN·폐쇄망 전제** — 외부 노출 금지.
  원격 접속이 안 되면 GPU 호스트 방화벽에서 `${GATEWAY_PORT}` 인바운드 허용 확인.

### Linux / macOS — `vscode-connect.sh`

```bash
./start.sh                    # 먼저 스택 기동 (gateway :8080 노출)

./vscode-connect.sh on        # ~/.claude/settings.json 병합(백업 후) → 게이트웨이 연결
./vscode-connect.sh status    # 현재 설정 + 게이트웨이 모델 목록
./vscode-connect.sh off       # 우리가 넣은 키만 제거 → Anthropic 복귀

# 적용 후 VSCode: 명령팔레트 → 'Developer: Reload Window'
```

* 넣는 값: `ANTHROPIC_BASE_URL=http://127.0.0.1:${GATEWAY_PORT}`, `ANTHROPIC_AUTH_TOKEN=lms`,
  `model=${LMS_MODEL}` (기존 키는 보존, 최초 실행 시 `settings.json.bak` 백업).
* **원격/다른 머신에서 접속**: `LMS_HOST=<GPU호스트IP> ./vscode-connect.sh on`.
* **워크스페이스로 한정**(전역 오염 회피): `CLAUDE_SETTINGS=.claude/settings.local.json ./vscode-connect.sh on`.

> ⚠️ **전역 설정을 바꾼다.** 기본 대상이 `~/.claude/settings.json` 이라, 적용하면 호스트의
> 모든 Claude Code(CLI·확장)가 로컬 LMS 로 향한다. 실제 Anthropic 로 되돌리려면 `off`
> (또는 `cp ~/.claude/settings.json.bak ~/.claude/settings.json`). 프로젝트에만 적용하려면
> 위 `CLAUDE_SETTINGS=` 워크스페이스 옵션을 쓸 것.

### Windows — `vscode-connect.ps1`

Windows 의 VSCode Claude Code 확장은 `%USERPROFILE%\.claude\settings.json` 을 읽는다. `.sh` 와
동일 키를 병합하는 PowerShell 판(5.1+, `jq` 불필요·BOM 없는 UTF-8 기록·최초 1회 `.bak` 백업)이
**`vscode-connect.ps1`** 이다. `.sh` 와 달리 `.env` 를 읽지 않고 **`-BaseUrl`·`-Model` 을 인자로 받는다**.

```powershell
# 실행정책에 막히면 앞에 -ExecutionPolicy Bypass
powershell -ExecutionPolicy Bypass -File .\vscode-connect.ps1 -Action on `
  -BaseUrl http://<GPU호스트IP>:8080 -Model google/gemma-4-e2b   # 게이트웨이 접속(원격)
#   -BaseUrl http://localhost:1234                                # (참고) 로컬 LM Studio 직결 시

.\vscode-connect.ps1 -Action status    # 현재 설정 + 게이트웨이 모델 목록
.\vscode-connect.ps1 -Action off        # 우리가 넣은 키만 제거 → Anthropic 복귀

# 적용 후 VSCode: 명령팔레트(Ctrl+Shift+P) → 'Developer: Reload Window'
```

* 넣는 값은 `.sh` 와 동일: `ANTHROPIC_BASE_URL`·`ANTHROPIC_AUTH_TOKEN=lms`·`API_TIMEOUT_MS`·
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`·`model`. `-Model` 은 게이트웨이가 서빙하는 키와 일치해야 함
  (`vscode-connect.ps1 -Action status` 로 목록 확인).
* `-Settings <경로>` 로 대상 파일 변경 가능(워크스페이스 `.claude\settings.local.json` 로 한정 시).
* 전역 설정을 바꾸는 것은 `.sh` 와 동일 — `off` 또는 `Copy-Item settings.json.bak settings.json` 로 원복.

> 참고: 학생 Windows PC 에 **로컬로 LM Studio 를 설치**해 각자 실습하는 수업용 절차는 jm4 Obsidian
> `3.Resource/_LLM/Tools/LM_Studio_Windows_ClaudeCode_수업.md` 참조(네이티브 설치 → `localhost:1234` 직결).
