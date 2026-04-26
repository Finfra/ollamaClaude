FROM ollama/ollama

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV ANTHROPIC_BASE_URL=http://127.0.0.1:11434
ENV ANTHROPIC_AUTH_TOKEN=ollama
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl ca-certificates bash vim git netcat-openbsd gosu && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Claude Code 전역 설치 (모든 유저에서 실행 가능)
RUN npm install -g @anthropic-ai/claude-code

# ubuntu 유저 생성 (UID 1000)
RUN groupadd -g 1000 ubuntu && \
    useradd -m -u 1000 -g 1000 -s /bin/bash ubuntu

RUN echo "alias cc='claude --dangerously-skip-permissions'" >> /home/ubuntu/.bashrc

RUN chown -R ubuntu:ubuntu /home/ubuntu

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/ubuntu

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
