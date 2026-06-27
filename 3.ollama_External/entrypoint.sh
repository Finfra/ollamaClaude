#!/bin/bash
# 컨테이너 PID 1 — 이미 USER=ubuntu 로 실행됨 (Dockerfile USER ubuntu)
#   - 외부(호스트/서버) Ollama 에 연결만 함. 컨테이너 내부에서 ollama serve 안 함
#   - OLLAMA_HOST: 외부 Ollama 호스트명 (기본 host.docker.internal)
#   - OLLAMA_PORT_EXT: 외부 Ollama 포트 (기본 11434)
set -e

OLLAMA_HOST="${OLLAMA_HOST:-host.docker.internal}"
OLLAMA_PORT_EXT="${OLLAMA_PORT_EXT:-11434}"

# ubuntu 의 claude settings.json 생성 (외부 Ollama 주소 반영)
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<JSON
{
  "model": "${OLLAMA_MODEL:-}",
  "env": {
    "ANTHROPIC_BASE_URL": "http://${OLLAMA_HOST}:${OLLAMA_PORT_EXT}",
    "ANTHROPIC_AUTH_TOKEN": "ollama"
  }
}
JSON

# 외부 Ollama 연결 확인 (해석 가능하면 대기, 아니면 경고 후 진행)
if getent hosts "$OLLAMA_HOST" >/dev/null 2>&1; then
  echo "[entrypoint] waiting for external Ollama at ${OLLAMA_HOST}:${OLLAMA_PORT_EXT} ..."
  TRIES=0
  until nc -z "$OLLAMA_HOST" "$OLLAMA_PORT_EXT" 2>/dev/null; do
    TRIES=$((TRIES+1))
    if [ "$TRIES" -ge 30 ]; then
      echo "[entrypoint] WARNING: external Ollama unreachable after 60s — continuing anyway"
      break
    fi
    echo "[entrypoint] Ollama unavailable - sleeping (${TRIES}/30)"
    sleep 2
  done
  if nc -z "$OLLAMA_HOST" "$OLLAMA_PORT_EXT" 2>/dev/null; then
    echo "[entrypoint] external Ollama is up - starting Claude Code environment"
  fi
else
  echo "[entrypoint] WARNING: host '${OLLAMA_HOST}' not resolvable - check extra_hosts / OLLAMA_HOST"
fi

exec "$@"
