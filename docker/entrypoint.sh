#!/usr/bin/env bash

set -e

if [ -n "${MONAD_VERSION_OVERRIDE:-}" ]; then
  log "Installing monad version override: ${MONAD_VERSION_OVERRIDE}"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
    --allow-downgrades \
    --allow-change-held-packages \
    "monad=${MONAD_VERSION_OVERRIDE}"
  echo "Monad version now:" && dpkg -l | grep "^ii  monad"
fi

generate-keys.sh
build-config.sh
start-node.sh
register-validator.sh

log "SOLONET NETWORK STARTED!"
echo
echo "Client version: $(monad-node --version 2>/dev/null)"
echo "Validators: ${TOTAL_VALIDATOR_NUMBER:-1}"
echo
echo "Cast tooling installed, get block with:"
echo "  cast block-number"
echo
echo "RPC endpoint: http://localhost:8080"
echo "BFT Logs:          /var/log/monda-bft.log"
echo "Execution Logs:    /var/log/monda-execution.log"
echo "RPC Logs:          /var/log/monda-rpc.log"
echo
echo "Override monad version with MONAD_VERSION_OVERRIDE environment variable"
echo

log "Starting Ledger tail logs..."
sleep 10
ln -s /home/monad/monad-bft/ /monad
while true; do
  /usr/local/bin/monad-ledger-tail | jq -C -c . || true
  sleep 1
done
