#!/bin/bash
# 6.lms_MultiLLM_run/start.sh
#   ─ 순수 docker run 기반 다중 LMS 백엔드 + nginx L7 분산 + claude 클라이언트.
#   ─ air-gap: docker compose 미설치 환경 대응 (5.lms_MultiLLM 을 이식).
#
# 전제:
#   - lms:latest, gateway:latest, claude:latest 이미지가 이미 로드됨 (docker load -i ...)
#     * 이미지 태그가 다르면 아래 LMS_IMAGE/GATEWAY_IMAGE/CLAUDE_IMAGE 를 .env 로 오버라이드
#   - 스크립트가 놓인 폴더에 entrypoint.sh, entrypoint.lms.sh, nginx.conf.template 이 함께 있음
#
# 스크립트가 하는 일:
#   1) .env 로드 → 기본값 병합
#   2) 네트워크 · 모델 볼륨 확보
#   3) lms-1..N 백엔드 기동 (--network-alias lms — Docker DNS 로 nginx 분산)
#      · entrypoint.lms.sh 를 5.lms_MultiLLM 판으로 override (:ro bind mount + --entrypoint)
#   4) 각 백엔드 /v1/models 헬스 폴링
#   5) gateway (nginx) 기동 — nginx.conf.template 를 :ro bind mount, ${LMS_PORT} envsubst
#   6) gateway /v1/models 폴링 (claude 기동 게이팅)
#   7) claude 기동 — entrypoint.sh 5.버전 override + GW_HOST/GW_PORT 주입
#
# 사용:
#   cp .env.org .env && vi .env
#   ./start.sh            # 기본 (GPU 사용)
#   USE_GPU=0 ./start.sh  # CPU 강제
#   ./start.sh --stop     # 전부 정지 + 제거
#   ./start.sh --status   # 컨테이너 상태 확인

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── .env 로드 (있으면) ─────────────────────────────────────────────────────
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
else
  echo "[warn] $ENV_FILE 없음 — 기본값 사용 (cp .env.org .env 권장)"
fi

# ── 기본값 (env.sh/.env.org 과 동기) ───────────────────────────────────────
: "${LMS_MODEL:=meta-llama-3.1-8b-instruct}"
: "${LMS_PORT:=1234}"
: "${LMS_HEALTH_TRIES:=30}"
: "${LMS_CONTEXT_LENGTH:=32768}"
: "${LMS_GPU:=}"          # 빈값=자동 offload (VRAM<모델크기 환경에서 max 는 CUDA OOM)
: "${LMS_PARALLEL:=1}"    # 슬롯 분할 방지 — Claude Code 는 1 필수 (ctx/슬롯수 = 슬롯당 ctx)
: "${LMS_MODEL_MOUNT:=lms-models}"        # 빈문자열이면 named volume, 절대경로면 bind
: "${GATEWAY_PORT:=8080}"
: "${LMS_BACKEND_COUNT:=2}"
: "${API_TIMEOUT_MS:=600000}"
: "${GATEWAY_CONTAINER_NAME:=gateway}"
: "${CLAUDE_CONTAINER_NAME:=claude}"
: "${LMS_NETWORK_NAME:=lms}"
: "${TZ:=Asia/Seoul}"
: "${USER_UID:=1000}"
: "${USER_GID:=1000}"

# 이미지 태그 (air-gap 로드된 이미지 이름과 일치해야 함)
: "${LMS_IMAGE:=lms:latest}"
: "${GATEWAY_IMAGE:=gateway:latest}"
: "${CLAUDE_IMAGE:=claude:latest}"

# 옵션
: "${USE_GPU:=1}"                          # 1=NVIDIA GPU, 0=CPU only
: "${MOUNT_CODE_DIR:=}"                    # 호스트 코드 폴더(선택, claude 마운트)
# Claude Code 출력 토큰 상한 — LMS 컨텍스트에 input+output 합산 예산이 필요.
# 기본 max_tokens(≈32k)가 그대로 가면 32k 컨텍스트 백엔드에서 500 발생.
: "${CLAUDE_MAX_OUTPUT_TOKENS:=8192}"
# 프롬프트 다이어트 (1=도구 4개만, 0=전체 24개) — entrypoint.sh 주석 참조
: "${CLAUDE_DIET:=1}"

CLAUDE_HOME_VOLUME="claude-home"

# ── 서브커맨드: stop / status ──────────────────────────────────────────────
case "${1:-}" in
  --stop|stop)
    echo "[*] 정지 및 제거"
    for i in $(seq 1 "$LMS_BACKEND_COUNT"); do
      docker rm -f "lms-$i" >/dev/null 2>&1 || true
    done
    docker rm -f "$GATEWAY_CONTAINER_NAME" "$CLAUDE_CONTAINER_NAME" >/dev/null 2>&1 || true
    echo "[+] 완료 (네트워크·볼륨은 유지 — 완전 정리는 아래 명령 참고)"
    echo "    docker network rm $LMS_NETWORK_NAME"
    echo "    docker volume  rm $CLAUDE_HOME_VOLUME $LMS_MODEL_MOUNT"
    exit 0 ;;
  --status|status)
    docker ps -a --filter "network=$LMS_NETWORK_NAME" \
      --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    exit 0 ;;
  --help|-h|help)
    grep -E '^# ' "$0" | sed 's/^# \?//'
    exit 0 ;;
esac

# ── 필수 파일 존재 확인 ────────────────────────────────────────────────────
for f in entrypoint.sh entrypoint.lms.sh nginx.conf.template; do
  [ -f "$SCRIPT_DIR/$f" ] || { echo "[!] $SCRIPT_DIR/$f 없음 — 폴더 이관 누락"; exit 1; }
done

echo "[*] 이미지 존재 확인"
for img in "$LMS_IMAGE" "$GATEWAY_IMAGE" "$CLAUDE_IMAGE"; do
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    echo "[!] 이미지 '$img' 없음 — 'docker load -i <tar>' 로 반입 후 재시도"
    echo "    (또는 .env 에서 *_IMAGE 오버라이드)"
    exit 1
  fi
done

# ── 1) 네트워크 ────────────────────────────────────────────────────────────
if ! docker network inspect "$LMS_NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$LMS_NETWORK_NAME" >/dev/null
  echo "[+] network 생성: $LMS_NETWORK_NAME"
else
  echo "[=] network 존재: $LMS_NETWORK_NAME"
fi

# ── 2) 모델 마운트 결정 (named volume vs bind mount) ───────────────────────
if [[ "$LMS_MODEL_MOUNT" == /* || "$LMS_MODEL_MOUNT" == \~* ]]; then
  # 호스트 경로 (bind mount)
  HOST_MODEL_DIR="${LMS_MODEL_MOUNT/#\~/$HOME}"
  mkdir -p "$HOST_MODEL_DIR"
  MODEL_MOUNT_OPT=(-v "$HOST_MODEL_DIR:/home/lms/.lmstudio/models")
  echo "[+] model mount(bind): $HOST_MODEL_DIR"
else
  # named volume
  docker volume inspect "$LMS_MODEL_MOUNT" >/dev/null 2>&1 || docker volume create "$LMS_MODEL_MOUNT" >/dev/null
  MODEL_MOUNT_OPT=(-v "$LMS_MODEL_MOUNT:/home/lms/.lmstudio/models")
  echo "[+] model mount(volume): $LMS_MODEL_MOUNT"
fi

# ── 3) LMS 백엔드 N개 기동 ──────────────────────────────────────────────────
GPU_OPT=()
[ "$USE_GPU" = "1" ] && GPU_OPT=(--gpus all)

echo "[*] LMS 백엔드 $LMS_BACKEND_COUNT 개 기동"
for i in $(seq 1 "$LMS_BACKEND_COUNT"); do
  NAME="lms-$i"
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" \
    --network "$LMS_NETWORK_NAME" \
    --network-alias lms \
    --restart unless-stopped \
    "${GPU_OPT[@]}" \
    "${MODEL_MOUNT_OPT[@]}" \
    -v "$SCRIPT_DIR/entrypoint.lms.sh:/usr/local/bin/entrypoint.lms.sh:ro" \
    --entrypoint /usr/local/bin/entrypoint.lms.sh \
    -e LMS_MODEL="$LMS_MODEL" \
    -e LMS_PORT="$LMS_PORT" \
    -e LMS_HEALTH_TRIES="$LMS_HEALTH_TRIES" \
    -e LMS_CONTEXT_LENGTH="$LMS_CONTEXT_LENGTH" \
    -e LMS_GPU="$LMS_GPU" \
    -e LMS_PARALLEL="$LMS_PARALLEL" \
    -e TZ="$TZ" \
    "$LMS_IMAGE" >/dev/null
  echo "  [+] $NAME 기동"
done

# ── 4) 각 LMS /v1/models 헬스 대기 (첫 백엔드만 정밀 대기, 나머진 확인만) ──
echo "[*] LMS /v1/models 헬스 대기 (최대 ~120s)"
WAIT_MAX=60
for i in $(seq 1 "$LMS_BACKEND_COUNT"); do
  NAME="lms-$i"
  TRIES=0
  until docker exec "$NAME" curl -fsS "http://127.0.0.1:${LMS_PORT}/v1/models" >/dev/null 2>&1; do
    TRIES=$((TRIES+1))
    if [ "$TRIES" -ge "$WAIT_MAX" ]; then
      echo "  [!] $NAME /v1/models 무응답 ($((WAIT_MAX*2))s) — 계속 진행"
      break
    fi
    sleep 2
  done
  [ "$TRIES" -lt "$WAIT_MAX" ] && echo "  [+] $NAME ready"
done

# ── 5) 게이트웨이(nginx) 기동 ──────────────────────────────────────────────
docker rm -f "$GATEWAY_CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --name "$GATEWAY_CONTAINER_NAME" \
  --network "$LMS_NETWORK_NAME" \
  --restart unless-stopped \
  -p "${GATEWAY_PORT}:8080" \
  -v "$SCRIPT_DIR/nginx.conf.template:/etc/nginx/templates/default.conf.template:ro" \
  -e LMS_PORT="$LMS_PORT" \
  -e TZ="$TZ" \
  "$GATEWAY_IMAGE" >/dev/null
echo "[+] $GATEWAY_CONTAINER_NAME 기동 (외부 포트 :$GATEWAY_PORT)"

# ── 6) gateway 헬스 대기 ───────────────────────────────────────────────────
echo "[*] gateway /v1/models 대기 (최대 ~90s)"
TRIES=0
until curl -fsS "http://127.0.0.1:${GATEWAY_PORT}/v1/models" >/dev/null 2>&1; do
  TRIES=$((TRIES+1))
  if [ "$TRIES" -ge 45 ]; then
    echo "[!] gateway 무응답 — claude 는 진행하되 로그 확인 권장 (docker logs $GATEWAY_CONTAINER_NAME)"
    break
  fi
  sleep 2
done
[ "$TRIES" -lt 45 ] && echo "[+] gateway ready"

# ── 7) claude 기동 ─────────────────────────────────────────────────────────
CODE_MOUNT_OPT=()
if [ -n "$MOUNT_CODE_DIR" ]; then
  HOST_CODE_DIR="${MOUNT_CODE_DIR/#\~/$HOME}"
  mkdir -p "$HOST_CODE_DIR"
  CODE_MOUNT_OPT=(-v "$HOST_CODE_DIR:/home/ubuntu/code")
  echo "[+] code mount: $HOST_CODE_DIR"
fi

docker volume inspect "$CLAUDE_HOME_VOLUME" >/dev/null 2>&1 || docker volume create "$CLAUDE_HOME_VOLUME" >/dev/null

DF_MOUNT_OPT=()
[ -d "$HOME/df" ] && DF_MOUNT_OPT=(-v "$HOME/df:/home/ubuntu/df")

docker rm -f "$CLAUDE_CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --name "$CLAUDE_CONTAINER_NAME" \
  --network "$LMS_NETWORK_NAME" \
  --restart unless-stopped \
  -it \
  -v "$CLAUDE_HOME_VOLUME:/home/ubuntu" \
  "${DF_MOUNT_OPT[@]}" \
  "${CODE_MOUNT_OPT[@]}" \
  -v "$SCRIPT_DIR/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro" \
  --entrypoint /usr/local/bin/entrypoint.sh \
  -e ANTHROPIC_BASE_URL="http://${GATEWAY_CONTAINER_NAME}:8080" \
  -e ANTHROPIC_AUTH_TOKEN=lms \
  -e ANTHROPIC_MODEL="$LMS_MODEL" \
  -e ANTHROPIC_SMALL_FAST_MODEL="$LMS_MODEL" \
  -e CLAUDE_CODE_MAX_OUTPUT_TOKENS="$CLAUDE_MAX_OUTPUT_TOKENS" \
  -e CLAUDE_DIET="$CLAUDE_DIET" \
  -e GW_HOST="$GATEWAY_CONTAINER_NAME" \
  -e GW_PORT=8080 \
  -e LMS_MODEL="$LMS_MODEL" \
  -e API_TIMEOUT_MS="$API_TIMEOUT_MS" \
  -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  -e TZ="$TZ" \
  "$CLAUDE_IMAGE" sleep infinity >/dev/null

echo "[+] $CLAUDE_CONTAINER_NAME 기동"
echo
echo "─────────────────────────────────────────────────────────────"
echo " 접속:  docker exec -it $CLAUDE_CONTAINER_NAME bash"
echo " 안에서: cc         # alias = claude --dangerously-skip-permissions"
echo " 게이트웨이: http://127.0.0.1:${GATEWAY_PORT}/v1/models"
echo " 상태:  $0 --status"
echo " 정지:  $0 --stop"
echo "─────────────────────────────────────────────────────────────"
