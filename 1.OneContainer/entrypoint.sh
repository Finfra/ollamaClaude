#!/bin/bash
set -e

# ollama serve는 root 권한으로 실행 (GPU/포트 접근 필요)
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

# ubuntu 유저용 settings.json 생성
mkdir -p /home/ubuntu/.claude
cat > /home/ubuntu/.claude/settings.json <<JSON
{
  "model": "${OLLAMA_MODEL:-}",
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:11434",
    "ANTHROPIC_AUTH_TOKEN": "ollama"
  }
}
JSON
chown -R ubuntu:ubuntu /home/ubuntu/.claude

# ubuntu 유저로 권한 드롭 후 CMD 실행
exec gosu ubuntu "$@"
