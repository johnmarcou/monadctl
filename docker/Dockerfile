FROM ubuntu:noble

ARG MONAD_VERSION=0.12.7

RUN echo "Types: deb\n\
URIs: https://pkg.category.xyz/\n\
Suites: noble\n\
Components: main\n\
Signed-By: /etc/apt/keyrings/category-labs.gpg" \
> /etc/apt/sources.list.d/category-labs.sources

RUN apt-get update \
  && apt-get install -y -qq curl gnupg nvme-cli aria2 jq ca-certificates parted cpulimit \
  && curl -fsSL https://pkg.category.xyz/keys/public-key.asc \
   | gpg --dearmor --yes -o /etc/apt/keyrings/category-labs.gpg

RUN apt-get update && apt-get install -y monad=${MONAD_VERSION}

ENTRYPOINT ["/entrypoint.sh"]
COPY entrypoint.sh /entrypoint.sh
COPY config/ /home/monad/monad-bft/config/
