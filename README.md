---
name: README
description: Ollama + Claude Code Docker 통합 환경 가이드
date: 2026-04-27
---

# 개요

Ollama 위에서 Claude Code를 실행하는 Docker 환경. 두 가지 구성 중 선택해서 사용함.

| 디렉토리         | 구성                  | 용도                                                              |
| :--------------- | :-------------------- | :---------------------------------------------------------------- |
| `1.OneContainer` | 단일 컨테이너         | 빠른 시작·로컬 개발. Ollama + Claude Code가 한 컨테이너에 동거    |
| `2.TwoContainer` | 분리 컨테이너 2개     | 운영·다중 클라이언트. Ollama 서비스를 독립시켜 재시작·공유 용이   |

공통 사전 요구사항:
* Docker / Docker Compose
* `.env` 파일에 `OLLAMA_MODEL=<모델명>` 지정 (ex: `OLLAMA_MODEL=gemma4:26b`)
* (Linux GPU 사용 시) NVIDIA Container Toolkit

# 1.OneContainer

## 용도

* 단일 머신에서 Ollama + Claude Code를 한 번에 띄우고 싶은 경우
* 컨테이너 1개만 관리하면 되므로 셋업·디버깅이 간결
* 외부에서 Ollama API를 별도로 공유할 필요 없는 1:1 환경

## 특징

* 베이스 이미지: `ollama/ollama` 위에 Node.js 22 + Claude Code + ubuntu 유저 추가
* Ollama 서버와 Claude CLI가 같은 컨테이너에서 실행 (`ANTHROPIC_BASE_URL=http://127.0.0.1:11434`)
* 호스트 포트 매핑: `11437 → 11434`
* 볼륨:
    - `~/df → /home/ubuntu/df` (작업 폴더)
    - `~/.ollama → /root/.ollama` (모델 저장)
    - `claude-home → /home/ubuntu` (Claude 홈 영속화)

## 사용법

```bash
cd 1.OneContainer

# Mac / Linux CPU 모드
docker compose up -d --build

# Linux + NVIDIA GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --build

# 컨테이너 접속 (ubuntu 유저)
docker exec -it -u ubuntu claude bash

# 컨테이너 내부에서 Claude Code 실행
cc          # alias = claude --dangerously-skip-permissions
```

> 처음 한 번은 퍼미션 오류가 날 수 있음. 두 번째 실행부터 정상 동작.

# 2.TwoContainer

## 용도

* Ollama 서버를 독립 컨테이너로 운영하고 싶은 경우 (재시작·로그 분리, 모니터링 용이)
* 같은 Ollama를 여러 클라이언트(Claude Code 외 다른 도구)와 공유
* claude 컨테이너만 자주 빌드/교체하고 ollama는 유지하고 싶은 환경

## 특징

* `ollama` 컨테이너: `ollama/ollama` 이미지 그대로, `${OLLAMA_MODEL}` 자동 pull
* `claude` 컨테이너: `debian:bookworm-slim` 기반의 경량 Claude Code 전용 이미지
* 컨테이너 간 통신: `claude` → `http://ollama:11434` (Docker 네트워크 `ollama`)
* 호스트 포트 매핑: `11436 → ollama:11434`
* `claude` 컨테이너는 ollama healthcheck가 통과한 후 기동 (`depends_on: service_healthy`)
* 볼륨:
    - `~/df → /df` (ollama) / `~/df → /home/ubuntu/df` (claude)
    - `~/.ollama → /root/.ollama` (ollama 전용, 모델 저장)
    - `claude-home → /home/ubuntu` (Claude 홈 영속화)

## 사용법

```bash
cd 2.TwoContainer

# Mac / Linux CPU 모드
docker compose up -d --build

# Linux + NVIDIA GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --build

# 클라이언트 접속 (ubuntu 유저, 기본 유저)
docker exec -it claude bash

# 컨테이너 내부에서 Claude Code 실행
cc

# Ollama 단독 재시작 (claude 영향 없음)
docker compose restart ollama
```

# 모드 비교 요약

| 항목                | 1.OneContainer                      | 2.TwoContainer                            |
| :------------------ | :---------------------------------- | :---------------------------------------- |
| 컨테이너 수         | 1                                   | 2 (`ollama`, `claude`)                    |
| Ollama 접근 (내부)  | `http://127.0.0.1:11434`            | `http://ollama:11434`                     |
| Ollama 접근 (호스트)| `http://localhost:11437`            | `http://localhost:11436`                  |
| 베이스 이미지       | `ollama/ollama` (확장)              | `ollama/ollama` + `debian:bookworm-slim` |
| Ollama 단독 재시작  | 불가 (claude까지 같이 내려감)        | 가능                                      |
| 다중 클라이언트 공유| 어려움                              | 용이                                      |

# 모델 설정

## 사용 가능 모델 예시

| 모델            | 용도      | 비고             |
| :-------------- | :-------- | :--------------- |
| qwen3-coder:30b | 코딩 특화 |                  |
| qwen3.5:35b     | 코딩 특화 |                  |
| qwen3.5:30b     | 코딩 특화 |                  |
| gemma4:26b      | 기본 모델 | 21.26 GB Mem 필요 |
| gemma4:31b      | 기본 모델 |                  |

## `.env` 로 통일 관리

```bash
# .env
OLLAMA_MODEL=gemma4:26b
```

| 적용 대상                | 동작                              |
| :----------------------- | :-------------------------------- |
| ollama 컨테이너 시작 시  | `ollama pull ${OLLAMA_MODEL}`     |
| claude 컨테이너 환경변수 | `ANTHROPIC_MODEL=${OLLAMA_MODEL}` |
| claude settings.json     | 컨테이너 시작 시 동적 생성        |

## 모델 전환

```bash
# 방법 1: .env 수정 후 재시작
vi .env   # OLLAMA_MODEL=qwen3-coder:30b
docker compose up -d

# 방법 2: 일회성 오버라이드
OLLAMA_MODEL=qwen3-coder:30b docker compose up -d

# 방법 3: 컨테이너 내에서 직접 지정 (이미 pull된 모델만)
claude --model qwen3-coder:30b
```

## qwen3 모델 사용 시 주의

qwen3 계열은 현재 작업 디렉토리를 자동 인식하지 못할 수 있음. 첫 프롬프트에서 명시:

```
현재 작업 폴더는 /home/ubuntu/df 입니다. 여기서 작업해주세요.
```

# 환경변수 (자동 주입)

| 변수                                       | 값                          | 설명                  |
| :----------------------------------------- | :-------------------------- | :-------------------- |
| `ANTHROPIC_BASE_URL`                       | 모드별 자동 설정            | Ollama API 엔드포인트 |
| `ANTHROPIC_AUTH_TOKEN`                     | `ollama`                    | 인증 토큰 (더미)      |
| `ANTHROPIC_MODEL`                          | `.env`의 `OLLAMA_MODEL`     | 기본 사용 모델        |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1`                         | 불필요 트래픽 차단    |

# 트러블슈팅

## Claude Code 가 Ollama에 연결되지 않을 때

```bash
# 환경변수 확인
docker exec claude bash -c 'echo $ANTHROPIC_BASE_URL'

# Ollama 연결 테스트 (1.OneContainer)
docker exec claude curl -s http://127.0.0.1:11434/api/tags

# Ollama 연결 테스트 (2.TwoContainer)
docker exec claude curl -s http://ollama:11434/api/tags
```

## CUDA OOM 에러 발생 시

* 대형 모델(qwen3-coder:30b, 18GB)은 16GB VRAM에서 CPU/GPU 분할 로드됨
* 검증된 최적화 환경변수 조합으로 VRAM 내 완전 로드 가능 (compose에 기본 설정됨)
    - `OLLAMA_FLASH_ATTENTION=1` — Flash Attention 활성화
    - `OLLAMA_KV_CACHE_TYPE=q8_0` — KV cache 8bit 양자화 (VRAM 절감 핵심)
    - `OLLAMA_NUM_GPU=999` — 전체 레이어 GPU 로드
    - `OLLAMA_CONTEXT_LENGTH=100000` — 100K context
* 여전히 OOM 시: `OLLAMA_FLASH_ATTENTION=0`으로 폴백 (성능 저하 감수)

## 모델 전환이 느릴 때

* Ollama는 모델 전환 시 기존 모델 언로드 → 새 모델 로드를 수행
* VRAM 16GB 제약으로 대형 모델 동시 로딩 불가
* 빠른 전환이 필요하면 소형 모델(7B~14B) 사용 권장

# 파일 구조

```
ollamaClaude/
├── 1.OneContainer/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── docker-compose.gpu.yml      # GPU override
│   ├── entrypoint.sh
│   └── .env -> ../.env             # 루트 .env로 심볼릭 링크
├── 2.TwoContainer/
│   ├── Dockerfile.claude
│   ├── docker-compose.yml
│   ├── docker-compose.gpu.yml      # GPU override
│   ├── test-setup.sh
│   └── .env -> ../.env             # 루트 .env로 심볼릭 링크
├── .env                            # OLLAMA_MODEL=...  (SSOT)
└── README.md
```

`.env` 는 루트에 1개만 두고 각 모드 디렉토리에서 심볼릭 링크로 공유함. 두 모드 모두 동일한 모델 설정을 따름.
