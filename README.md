---
name: README
description: Ollama + Claude Code Docker 통합 환경 가이드
date: 2026-04-09
---

# 구성

* **ollama 컨테이너**: GPU 지원 Ollama 서버 (`.env`에서 지정한 모델 자동 pull)
* **claude 컨테이너**: Claude Code 실행 환경 (ubuntu 유저 기본)

# 사용법

## 볼륨 디렉토리 생성 (최초 1회)

```bash
mkdir -p ~/localLLM/df ~/localLLM/ollama_docker
```

## 컨테이너 빌드 & 시작

```bash
# Mac (CPU 모드)
docker compose up -d --build

# Linux + NVIDIA GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d --build
```

* 기본 `docker-compose.yml`은 Mac·Linux 공통 (CPU 모드로 동작)
* `docker-compose.gpu.yml`은 NVIDIA GPU 할당만 추가하는 override 파일
* Mac에서 `dcu`(=`docker-compose up`) 그대로 사용 가능

## Claude 컨테이너 접속

```bash
docker exec -it claude bash
```

## Claude Code 실행

> **주의**: 처음 한 번은 퍼미션 문제로 실행 안 됨. 2번째부터 실행하면 사용 가능.

```bash
alias cc='claude --dangerously-skip-permissions'
cc   # 1번째: 퍼미션 에러 발생 (정상)
cc   # 2번째: 정상 실행
```

# 멀티 모델 사용

## 사용 가능 모델
| 모델            | 용도      | 비고             |
| --------------- | --------- | ---------------- |
| qwen3-coder:30b | 코딩 특화 |                  |
| qwen3.5:35b     | 코딩 특화 |                  |
| qwen3.5:30b     | 코딩 특화 |                  |
| gemma4:26b      | 기본 모델 | 21.26 GB Mem필요 |
| gemma4:31b      | 기본 모델 |                  |

* cf1) ollama launch claude --model gemma4:26b (메모리 부족하지만 않으면 작동함.)
* cf2) https://ttj.kr/tech-news/gemma-4를-내-컴퓨터에서-돌리고-claude-code와-연결하기-lm-studio-헤드리스-cli-활용법

## 모델 설정 (.env)

`.env` 파일 하나로 모든 모델 설정 통일:

```bash
# .env
OLLAMA_MODEL=gemma4:26b
```

이 변수가 적용되는 곳:

| 적용 대상                | 동작                              |
| :----------------------- | :-------------------------------- |
| ollama 컨테이너 시작 시  | `ollama pull ${OLLAMA_MODEL}`     |
| claude 컨테이너 환경변수 | `ANTHROPIC_MODEL=${OLLAMA_MODEL}` |
| claude settings.json     | 컨테이너 시작 시 동적 생성        |

## 모델 전환 방법

```bash
# 방법 1: .env 수정 후 재시작
vi .env   # OLLAMA_MODEL=qwen3-coder:30b
docker compose up -d

# 방법 2: 실행 시 오버라이드 (일회성)
OLLAMA_MODEL=qwen3-coder:30b docker compose up -d

# 방법 3: 컨테이너 내에서 직접 지정 (pull 된 모델만)
claude --model qwen3-coder:30b
```

## 모델 추가

### 1. `.env` 변경

```bash
OLLAMA_MODEL=<새모델>
```

### 2. 컨테이너 재시작

```bash
docker compose up -d
```

## qwen3 모델 사용 시 주의사항

qwen3 모델은 현재 작업 폴더를 인식 못할 수 있음. 첫 프롬프트에서 작업 디렉토리를 알려줘야 함.

```
현재 작업 폴더는 /home/ubuntu/test 입니다. 여기서 작업해주세요.
```

# 환경변수

모든 유저(root, ubuntu)에서 자동 로드:

| 변수                                       | 값                      | 설명                  |
| ------------------------------------------ | ----------------------- | --------------------- |
| `ANTHROPIC_BASE_URL`                       | `http://ollama:11434`   | Ollama API 엔드포인트 |
| `ANTHROPIC_AUTH_TOKEN`                     | `ollama`                | 인증 토큰             |
| `ANTHROPIC_MODEL`                          | `.env`의 `OLLAMA_MODEL` | 기본 사용 모델        |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1`                     | 불필요 트래픽 차단    |

# 볼륨 구성

| 호스트 경로                  | 컨테이너 경로                | 용도             |
| ---------------------------- | ---------------------------- | ---------------- |
| `~/localLLM/df`              | ollama: `/df`                | 공유 데이터 폴더 |
|                              | claude: `/home/ubuntu/df` | 공유 데이터 폴더 |
| `~/localLLM/ollama_docker`   | `/root/.ollama`              | Ollama 모델 저장 |
| `claude-home` (named volume) | `/home/ubuntu`            | Claude 홈 영속화 |

# 네트워크

| 접근 방법     | URL                      | 비고            |
| ------------- | ------------------------ | --------------- |
| 컨테이너 내부 | `http://ollama:11434`    | Docker 네트워크 |
| 호스트        | `http://localhost:11436` | Docker Compose  |
| 기존 systemd  | `http://localhost:11434` | ollama 유저     |
| 기존 nowage   | `http://localhost:11435` | nowage 유저     |

# 트러블슈팅

## Claude Code 실행 안될 때

```bash
# 환경변수 확인
echo $ANTHROPIC_BASE_URL

# Ollama 연결 테스트
curl http://ollama:11434/api/tags
```

## CUDA OOM 에러 발생 시

* qwen3-coder:30b (18GB)는 RTX 4070 Ti SUPER (16GB VRAM)에서 원래 CPU/GPU 분할 로드됨
* 검증된 최적화 환경변수 조합으로 VRAM 내 완전 로드 가능 (docker-compose.yml ollama 서비스에 설정됨)
    - `OLLAMA_FLASH_ATTENTION=1` — Flash Attention 활성화 (성능 ↑)
    - `OLLAMA_KV_CACHE_TYPE=q8_0` — KV cache 8bit 양자화 (VRAM 절감 핵심)
    - `OLLAMA_NUM_GPU=999` — 전체 레이어 GPU 로드
    - `OLLAMA_CONTEXT_LENGTH=100000` — 100K context 확보
* 여전히 OOM 발생 시: `OLLAMA_FLASH_ATTENTION=0`으로 폴백(성능 저하 감수)

## 모델 전환이 느릴 때

* Ollama는 모델 전환 시 기존 모델 언로드 → 새 모델 로드 수행
* VRAM 16GB 제약으로 대형 모델 동시 로딩 불가
* 빠른 전환이 필요하면 소형 모델(7B~14B급) 사용 권장

# 파일 구조

| 파일                 | 설명                          |
| :------------------- | :---------------------------- |
| `.env`               | 모델 설정 (OLLAMA_MODEL)      |
| `docker-compose.yml` | 서비스 정의 (ollama + claude) |
| `Dockerfile.claude`  | Claude Code 컨테이너 빌드     |
| `test-setup.sh`      | 환경 테스트 스크립트          |
