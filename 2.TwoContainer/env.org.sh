# 모델 설정
OLLAMA_MODEL=qwen3.5:latest

# 호스트 ~/.ollama 와 모델 공유 여부
# 공유: OLLAMA_MOUNT=~/.ollama
# 격리(컨테이너 named volume): OLLAMA_MOUNT=ollama-models
OLLAMA_MOUNT=~/.ollama

# 호스트 코드 폴더 마운트 (선택)
# 사용 시 docker-compose.code.yml override 적용
# MOUNT_CODE_DIR=~/code
MOUNT_CODE_DIR=
