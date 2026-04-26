#!/bin/bash
# volume 마운트 후 초기화 (root로 실행)

# .bashrc가 없거나 비어있으면 복원
if [ ! -s /home/ubuntu/.bashrc ]; then
    cat > /home/ubuntu/.bashrc <<'EOF'
export LC_ALL=C.UTF-8
export ANTHROPIC_BASE_URL=http://ollama:11434
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=ollama
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
EOF
fi

# settings.json 없으면 생성
if [ ! -f /home/ubuntu/.claude/settings.json ]; then
    mkdir -p /home/ubuntu/.claude
    cat > /home/ubuntu/.claude/settings.json <<'SETTINGS'
{
  "model": "qwen3-coder:30b",
  "env": {
    "ANTHROPIC_BASE_URL": "http://ollama:11434",
    "ANTHROPIC_AUTH_TOKEN": "ollama"
  }
}
SETTINGS
fi

# 소유권 보정
chown -R ubuntu:ubuntu /home/ubuntu

# ubuntu로 전환하여 실행
exec gosu ubuntu sleep infinity
