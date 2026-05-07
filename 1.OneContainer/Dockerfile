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

RUN chown -R ubuntu:ubuntu /home/ubuntu

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/ubuntu

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
