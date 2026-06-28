#!/bin/bash
# 컨테이너 PID 1 — 이미 USER=ubuntu 로 실행됨 (Dockerfile USER ubuntu)
#   - ollama 는 ubuntu 의 $HOME/.ollama 를 모델 디렉토리로 사용
#   - 11434 는 비특권 포트, GPU 는 nvidia-container-toolkit 가 노출하므로 root 불필요
set -e

/bin/ollama serve &
OLLAMA_PID=$!

until ollama list >/dev/null 2>&1; do
  echo "[entrypoint] waiting for ollama..."
  sleep 2
done
echo "[entrypoint] ollama is up"

if [ -n "$OLLAMA_MODEL" ]; then
  ollama pull "$OLLAMA_MODEL" || echo "[entrypoint] WARNING: model pull failed: $OLLAMA_MODEL"
fi

# ubuntu 의 claude settings.json 생성
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<JSON
{
  "model": "${OLLAMA_MODEL:-}",
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:11434",
    "ANTHROPIC_AUTH_TOKEN": "ollama"
  }
}
JSON

exec "$@"
