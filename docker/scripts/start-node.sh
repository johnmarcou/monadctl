#!/usr/bin/env bash

set -e

log "Prepare triedb device"
fallocate -l 100G /loopfile.img
DEVICE="/dev/loop$VAL_ID"
losetup -d "$DEVICE" || true
losetup "$DEVICE" /loopfile.img
ln -s "$DEVICE" /dev/triedb || true
monad-mpt --create --storage /dev/triedb

if [[ -f /shared/forkpoint.toml ]]; then
  log "Network already started, fetching forkpoint"
  cp /shared/forkpoint.toml /home/monad/monad-bft/config/forkpoint/forkpoint.toml
  cp /shared/validators.toml /home/monad/monad-bft/config/validators/validators.toml
else
  log "Create Genesis block"
  monad --chain monad_devnet \
    --db /dev/triedb \
    --block_db ./monad-bft/ledger \
    --nblocks 0 \
    --log_level INFO
fi

log "Start loop to copy forkpoint and validators to shared folder"
while true; do
  cp /home/monad/monad-bft/config/forkpoint/forkpoint.toml /shared/forkpoint.toml
  cp /home/monad/monad-bft/config/validators/validators.toml /shared/validators.toml
  sleep 1
done &

log "Start OTEL"
/usr/bin/otelcol --config=/etc/otelcol/config.yaml \
  >/var/log/monad-otel.log 2>&1 &

log "Start RPC"
cpulimit -l 50 -- monad-rpc \
  --ipc-path /home/monad/monad-bft/mempool.sock \
  --triedb-path /dev/triedb \
  --otel-endpoint "http://0.0.0.0:4317" \
  --allow-unprotected-txs \
  --node-config /home/monad/monad-bft/config/node.toml \
  >/var/log/monad-rpc.log 2>&1 &

log "Start Execution"
cpulimit -l 50 -- monad \
  --chain monad_devnet \
  --db /dev/triedb \
  --block_db /home/monad/monad-bft/ledger \
  --statesync /home/monad/monad-bft/statesync.sock \
  --log_level ERROR \
  >/var/log/monad-execution.log 2>&1 &

log "Start BFT"
export RUST_LOG=debug,h2=warn,tower=warn,opentelemetry_sdk=warn,opentelemetry-otlp=warn
exec monad-node \
  --triedb-path /dev/triedb \
  --secp-identity /home/monad/monad-bft/config/id-secp \
  --bls-identity /home/monad/monad-bft/config/id-bls \
  --node-config /home/monad/monad-bft/config/node.toml \
  --forkpoint-config /home/monad/monad-bft/config/forkpoint/forkpoint.toml \
  --wal-path /home/monad/monad-bft/wal \
  --mempool-ipc-path /home/monad/monad-bft/mempool.sock \
  --persisted-peers-path /home/monad/monad-bft/config/peers.toml \
  --control-panel-ipc-path /home/monad/monad-bft/controlpanel.sock \
  --statesync-ipc-path /home/monad/monad-bft/statesync.sock \
  --ledger-path /home/monad/monad-bft/ledger \
  --otel-endpoint "http://0.0.0.0:4317" \
  --record-metrics-interval-seconds 1 \
  --validators-path /home/monad/monad-bft/config/validators/validators.toml \
  --keystore-password password \
  >/var/log/monad-bft.log 2>&1 &
