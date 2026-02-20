#!/usr/bin/env bash

set -e

generate-keys.sh
build-config.sh
start-node.sh
register-validator.sh

log "Start ledger tail"
ln -s /home/monad/monad-bft/ /monad
while true; do
  /usr/local/bin/monad-ledger-tail | jq -C -c . || true
  sleep 1
done
