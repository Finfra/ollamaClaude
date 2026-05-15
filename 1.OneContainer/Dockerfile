FROM ollama/ollama

ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV ANTHROPIC_BASE_URL=http://127.0.0.1:11434
ENV ANTHROPIC_AUTH_TOKEN=ollama
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates bash vim git netcat-openbsd gosu tzdata && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Claude Code 전역 설치 (모든 유저에서 실행 가능)
RUN npm install -g @anthropic-ai/claude-code

# Claude Code wrapper — Ollama 컨테이너 환경에서 trust dialog / 권한 prompt 자동 우회
#   - /usr/local/bin/claude (PATH 우선) 와 /usr/bin/claude (npm 심볼릭 자리) 둘 다 wrapper 로 통일
#   - ollama launch claude / 직접 호출 / 절대경로 호출 모두 동일 동작 보장
#   - 원본 바이너리는 /usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe 그대로 보존
RUN printf '%s\n' \
      '#!/usr/bin/env bash' \
      '# Auto-inject --dangerously-skip-permissions for the Ollama+Claude container.' \
      '# Container isolation already provides the safety boundary; the prompt only blocks UX.' \
      'exec /usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe --dangerously-skip-permissions "$@"' \
      > /usr/local/bin/claude && \
    chmod +x /usr/local/bin/claude && \
    ln -sf /usr/local/bin/claude /usr/bin/claude

# ubuntu 유저 생성 (UID/GID 가변, 기본 1000) — 베이스 이미지에 이미 존재하면 재맞춤
RUN if getent group ubuntu >/dev/null 2>&1; then \
        groupmod -g ${USER_GID} ubuntu; \
    else \
        groupadd -g ${USER_GID} ubuntu; \
    fi && \
    if id -u ubuntu >/dev/null 2>&1; then \
        usermod -u ${USER_UID} -g ${USER_GID} ubuntu; \
    else \
        useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ubuntu; \
    fi && \
    (test -d /home/ubuntu || mkdir -p /home/ubuntu)

RUN echo "alias cc='claude --dangerously-skip-permissions'" >> /home/ubuntu/.bashrc

# ollama 모델 디렉토리를 ubuntu 홈에 미리 생성·소유권 부여
#   - ollama 가 ubuntu 로 실행되면 $HOME/.ollama 를 자동 사용
#   - compose 의 volume 마운트도 /home/ubuntu/.ollama 로 일치
RUN mkdir -p /home/ubuntu/.ollama && \
    chown -R ubuntu:ubuntu /home/ubuntu

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/ubuntu

# docker exec 기본 유저를 ubuntu 로 — 명시적 `-u root` 는 그대로 root 진입
USER ubuntu

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
