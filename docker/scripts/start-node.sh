#!/usr/bin/env bash

log "Prepare triedb device"
fallocate -l 100G /loopfile.img
DEVICE="/dev/loop$VAL_ID"
losetup -d "$DEVICE" || true
losetup "$DEVICE" /loopfile.img
ln -s "$DEVICE" /dev/triedb
monad-mpt --create --storage /dev/triedb

log "Create Genesis block"
monad --chain monad_devnet \
  --db /dev/triedb \
  --block_db ./monad-bft/ledger \
  --nblocks 0 \
  --log_level INFO

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
monad-node \
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

log "Start ledger tail"
ln -s /home/monad/monad-bft monad
while true; do
  /usr/local/bin/monad-ledger-tail | jq -C -c . || true
  sleep 1
done
