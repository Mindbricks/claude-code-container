FROM node:24-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    bash \
    less \
    jq \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

ARG CLAUDE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION}

ENV PATH="/root/.local/bin:$PATH"
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN uv python install 3.12.6

WORKDIR /workspace

ENTRYPOINT ["claude"]
