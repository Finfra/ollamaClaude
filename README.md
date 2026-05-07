---
name: README
description: Ollama + Claude Code Docker 통합 환경 가이드
date: 2026-05-07
---

# 개요

Ollama 위에서 Claude Code를 실행하는 Docker 환경. 두 가지 구성 중 선택해서 사용함.

| 디렉토리         | 구성                  | 용도                                                              |
| :--------------- | :-------------------- | :---------------------------------------------------------------- |
| `1.OneContainer` | 단일 컨테이너         | 빠른 시작·로컬 개발. Ollama + Claude Code가 한 컨테이너에 동거    |
| `2.TwoContainer` | 분리 컨테이너 2개     | 운영·다중 클라이언트. Ollama 서비스를 독립시켜 재시작·공유 용이   |

공통 사전 요구사항:
* Docker / Docker Compose (v2 권장 — `.env` 자동 로드 + 틸드 확장 지원)
* 각 컨테이너 폴더의 `.env` 준비 (아래 참조)
* (Linux GPU 사용 시) NVIDIA Container Toolkit

## .env 설정

각 컨테이너 폴더에 독립된 `.env`를 두는 방식 (이전 루트 공용 `.env` + 심볼릭 링크 폐기).

```bash
# 1.OneContainer
cd 1.OneContainer
cp .env.org .env
vi .env          # OLLAMA_MODEL, OLLAMA_MOUNT, MOUNT_CODE_DIR 수정

# 2.TwoContainer
cd 2.TwoContainer
cp .env.org .env
vi .env
```

* `.env.org` — 커밋된 템플릿 (KEY=VALUE 형식)
* `.env` — 사용자 복사본 (`.gitignore`로 커밋 금지)
* docker compose가 같은 폴더의 `.env`를 자동 로드하므로 별도 `--env-file` 옵션 불필요

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
    - `${OLLAMA_MOUNT} → /root/.ollama` (모델 저장, 토글 가능)
    - `claude-home → /home/ubuntu` (Claude 홈 영속화)

## 사용법

```bash
cd 1.OneContainer

# Mac / Linux CPU 모드
docker compose up -d --build

# Linux + NVIDIA GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --build

# 호스트 코드 폴더 마운트 (선택)
docker compose -f docker-compose.yml -f docker-compose.code.yml up -d --build

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
    - `${OLLAMA_MOUNT} → /root/.ollama` (ollama 전용, 모델 저장, 토글 가능)
    - `claude-home → /home/ubuntu` (Claude 홈 영속화)

## 사용법

```bash
cd 2.TwoContainer

# Mac / Linux CPU 모드
docker compose up -d --build

# Linux + NVIDIA GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --build

# 호스트 코드 폴더 마운트 (선택)
docker compose -f docker-compose.yml -f docker-compose.code.yml up -d --build

# 클라이언트 접속 (ubuntu 유저, 기본 유저)
docker exec -it claude bash

# 컨테이너 내부에서 Claude Code 실행
cc

# Ollama 단독 재시작 (claude 영향 없음)
docker compose restart ollama
```

# 모드 비교 요약

| 항목                | 1.OneContainer                                                  | 2.TwoContainer                                                  |
| :------------------ | :-------------------------------------------------------------- | :-------------------------------------------------------------- |
| 컨테이너 수         | 1                                                               | 2 (`ollama`, `claude`)                                          |
| Ollama 접근 (내부)  | `http://127.0.0.1:11434`                                        | `http://ollama:11434`                                           |
| Ollama 접근 (호스트)| `http://localhost:11437`                                        | `http://localhost:11436`                                        |
| 베이스 이미지       | `ollama/ollama` (확장)                                          | `ollama/ollama` + `debian:bookworm-slim`                        |
| Ollama 단독 재시작  | 불가 (claude까지 같이 내려감)                                    | 가능                                                            |
| 다중 클라이언트 공유| 어려움                                                          | 용이                                                            |
| 모델 저장소 토글    | `OLLAMA_MOUNT` (공유: `~/.ollama` / 격리: `ollama-models`)      | 동일                                                            |
| 코드 폴더 마운트    | `MOUNT_CODE_DIR` + `docker-compose.code.yml`                    | 동일                                                            |

# 마운트 옵션

## 모델 저장소 토글 (`OLLAMA_MOUNT`)

`.env`의 `OLLAMA_MOUNT` 값으로 모델 디렉토리(`/root/.ollama`)의 호스트측 위치를 전환함.

| 값                         | 동작                                                                                     |
| :------------------------- | :--------------------------------------------------------------------------------------- |
| `~/.ollama` (기본)         | 호스트 모델 디렉토리 공유. 호스트에서 `ollama pull`한 모델을 컨테이너에서도 그대로 사용  |
| `ollama-models`            | docker named volume에 격리. 컨테이너만의 깨끗한 저장소. 호스트와 분리                    |
| 그 외 절대 경로 / volume명 | 임의 경로 또는 임의 named volume                                                         |

docker compose는 값이 `/`, `~`, `.`로 시작하면 bind mount, 그 외 식별자는 named volume으로 자동 분기함.

## 호스트 코드 마운트 (`MOUNT_CODE_DIR`)

호스트의 코드 폴더를 컨테이너 내 `/home/ubuntu/code`로 마운트하는 옵션. `docker-compose.code.yml` override로 분리되어 있어 필요한 경우에만 적용함.

```bash
# .env에 설정
MOUNT_CODE_DIR=~/code

# 실행 시 override 추가
docker compose -f docker-compose.yml -f docker-compose.code.yml up -d
```

`MOUNT_CODE_DIR`이 비어 있으면 override 파일을 적용하지 않으면 됨 (기본 `docker-compose.yml`만 사용).

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

| 변수                                       | 값                          | 설명                                            |
| :----------------------------------------- | :-------------------------- | :---------------------------------------------- |
| `ANTHROPIC_BASE_URL`                       | 모드별 자동 설정            | Ollama API 엔드포인트                           |
| `ANTHROPIC_AUTH_TOKEN`                     | `ollama`                    | 인증 토큰 (더미)                                |
| `ANTHROPIC_MODEL`                          | `.env`의 `OLLAMA_MODEL`     | 기본 사용 모델                                  |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1`                         | 불필요 트래픽 차단                              |
| `OLLAMA_MOUNT`                             | `.env` 값                   | 모델 저장소 위치 (호스트 경로 또는 named volume)|
| `MOUNT_CODE_DIR`                           | `.env` 값 (선택)            | 호스트 코드 폴더 경로 (override 적용 시)        |
| `OLLAMA_FLASH_ATTENTION`                   | `1` (기본)                  | Flash Attention on/off                          |
| `OLLAMA_KV_CACHE_TYPE`                     | `q8_0` (기본)               | KV cache 양자화 (`f16`/`q8_0`/`q4_0`)           |
| `OLLAMA_NUM_GPU`                           | `999` (기본)                | GPU 레이어 수                                   |
| `OLLAMA_CONTEXT_LENGTH`                    | `100000` (기본)             | 컨텍스트 길이                                   |
| `TZ`                                       | `Asia/Seoul` (기본)         | 컨테이너 내 타임존 (`date`, git commit, 로그)   |
| `COMPOSE_PROJECT_NAME`                     | 모드별 기본값               | docker compose 프로젝트명 (충돌 회피)            |
| `CLAUDE_CONTAINER_NAME` / `OLLAMA_CONTAINER_NAME` | `claude`/`ollama`     | 컨테이너 이름 (다중 인스턴스 시 변경)           |
| `OLLAMA_PORT`                              | `11437`/`11436`             | 호스트 측 노출 포트                             |
| `USER_UID` / `USER_GID`                    | `1000` (기본)               | 컨테이너 ubuntu 유저 UID/GID (Dockerfile build) |

# 다중 인스턴스 운영

같은 호스트에서 두 모드를 동시에 띄우거나 여러 카피를 운영하려면 `.env`에서 충돌 가능 변수만 다르게 설정:

```bash
# 인스턴스 A (.env)
COMPOSE_PROJECT_NAME=ollama_claude_one_a
CLAUDE_CONTAINER_NAME=claude_a
OLLAMA_PORT=11437

# 인스턴스 B (.env, 다른 폴더 복사본)
COMPOSE_PROJECT_NAME=ollama_claude_one_b
CLAUDE_CONTAINER_NAME=claude_b
OLLAMA_PORT=11447
```

2.TwoContainer는 추가로 `OLLAMA_CONTAINER_NAME`, `OLLAMA_NETWORK_NAME`도 분리.

# UID/GID 매핑 (Linux 호스트 + 코드 마운트)

`MOUNT_CODE_DIR`로 호스트 코드 폴더를 마운트할 때 컨테이너↔호스트 권한 일치를 위해 UID/GID 맞춤:

```bash
# 호스트 UID/GID 확인
id -u    # ex) 1001
id -g    # ex) 1001

# .env 수정
USER_UID=1001
USER_GID=1001

# 이미지 재빌드 (build args 변경 반영 필수)
docker compose build --no-cache
docker compose up -d
```

* macOS Docker Desktop은 자동 위임으로 1000 그대로도 OK
* Linux 호스트는 코드 마운트 시 권한 사고 방지 위해 반드시 일치 권장

# 트러블슈팅

## .env 누락 시

`docker compose up` 실행 시 변수 미정의 경고:

```bash
cd 1.OneContainer  # 또는 2.TwoContainer
cp .env.org .env
```

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
* 양쪽 모드 모두 `.env`에 다음 변수가 외부화되어 yml 수정 없이 조정 가능:
    - `OLLAMA_FLASH_ATTENTION=1` — Flash Attention 활성화
    - `OLLAMA_KV_CACHE_TYPE=q8_0` — KV cache 8bit 양자화 (VRAM 절감 균형, 기본)
        - `f16`: 양자화 없음, 정확도 우선 (24GB+ VRAM)
        - `q4_0`: 4bit 양자화, VRAM 최소 (8~12GB VRAM, 품질 일부 희생)
    - `OLLAMA_NUM_GPU=999` — 전체 레이어 GPU 로드
    - `OLLAMA_CONTEXT_LENGTH=100000` — 100K context
* 여전히 OOM 시: `OLLAMA_FLASH_ATTENTION=0` 또는 `OLLAMA_KV_CACHE_TYPE=q4_0`로 폴백

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
│   ├── docker-compose.gpu.yml       # GPU override
│   ├── docker-compose.code.yml      # NEW: 코드 마운트 override
│   ├── entrypoint.sh
│   ├── .env.org                     # NEW: 커밋된 템플릿
│   └── .env                         # NEW: 사용자 복사본 (.gitignore)
├── 2.TwoContainer/
│   ├── Dockerfile.claude
│   ├── docker-compose.yml
│   ├── docker-compose.gpu.yml       # GPU override
│   ├── docker-compose.code.yml      # NEW: 코드 마운트 override
│   ├── test-setup.sh
│   ├── .env.org                     # NEW: 커밋된 템플릿
│   └── .env                         # NEW: 사용자 복사본 (.gitignore)
└── README.md
```

각 컨테이너 폴더가 독립된 `.env`를 보유함 (docker compose 자동 로드). 루트의 공용 `env`/`.env`와 심볼릭 링크는 폐지됨.
