# 모델 설정
# 사용할 Ollama 모델 태그를 지정함 : qwen3.5:35b qwen3.5:27b gemma4:26b gemma4:31b
OLLAMA_MODEL=gemma4

# 호스트 ~/.ollama 와 모델 공유 여부
# - 공유 (호스트 모델 재사용): OLLAMA_MOUNT=~/.ollama
# - 격리 (컨테이너 named volume 사용): OLLAMA_MOUNT=ollama-models
OLLAMA_MOUNT=~/.ollama

# 호스트 코드 폴더 마운트 (선택)
# 사용 시 docker-compose.code.yml override 를 함께 적용
# 예: docker compose -f docker-compose.yml -f docker-compose.code.yml up -d
# MOUNT_CODE_DIR=~/code
MOUNT_CODE_DIR=
