FROM ubuntu:noble

ARG MONAD_VERSION=0.12.7

RUN echo "Types: deb\n\
URIs: https://pkg.category.xyz/\n\
Suites: noble\n\
Components: main\n\
Signed-By: /etc/apt/keyrings/category-labs.gpg" \
> /etc/apt/sources.list.d/category-labs.sources

RUN apt-get update \
  && apt-get install -y -qq \
    aria2 \
    ca-certificates \
    cpulimit \
    curl \
    git \
    gnupg \
    jq \
    nvme-cli \
    parted \
    pipx \
    python3 \
    vim \
  && curl -fsSL https://pkg.category.xyz/keys/public-key.asc \
   | gpg --dearmor --yes -o /etc/apt/keyrings/category-labs.gpg

RUN apt-get update && apt-get install -y monad=${MONAD_VERSION}

RUN  OTEL_VERSION="0.139.0" \
  && OTEL_PACKAGE="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/otelcol_${OTEL_VERSION}_linux_amd64.deb" \
  && curl -fsSL "$OTEL_PACKAGE" -o /tmp/otelcol_linux_amd64.deb \
  && dpkg -i /tmp/otelcol_linux_amd64.deb \
  && cp /opt/monad/scripts/otel-config.yaml /etc/otelcol/config.yaml

WORKDIR /root/
RUN git clone https://github.com/monad-developers/staking-sdk-cli.git \
  && cd staking-sdk-cli \
  && python3 -m venv cli-venv \
  && . cli-venv/bin/activate \
  && pip install . \
  && printf '%s\n' \
  '#!/usr/bin/env bash' \
  '/root/staking-sdk-cli/cli-venv/bin/python /root/staking-sdk-cli/staking-cli/main.py "$@"' \
  > /usr/local/bin/staking-cli \
  && chmod +x /usr/local/bin/staking-cli

RUN curl -L https://foundry.paradigm.xyz | bash  && . ~/.bashrc && foundryup
ENV ETH_RPC_URL="http://localhost:8080"

ENTRYPOINT ["/entrypoint.sh"]
COPY entrypoint.sh /entrypoint.sh
COPY config/ /home/monad/monad-bft/config/
COPY scripts/* /usr/local/bin/.
