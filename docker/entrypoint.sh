#!/usr/bin/env bash

set -e

log() {
  local msg="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")

  echo
  echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;32m[$ts]\033[0m \033[1m$msg\033[0m"
  echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
}

log "Set kernel parameters"
echo 4 >/sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages
echo 2048 >/sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages

log "Generate keys"
monad-keystore create \
  --key-type secp \
  --keystore-path /home/monad/monad-bft/config/id-secp \
  --password password >/opt/monad/backup/secp-backup
monad-keystore create \
  --key-type bls \
  --keystore-path /home/monad/monad-bft/config/id-bls \
  --password password >/opt/monad/backup/bls-backup
SECP_PUBKEY=$(grep "public key" /opt/monad/backup/secp-backup | cut -d " " -f4)
BLS_PUBKEY=$(grep "public key" /opt/monad/backup/bls-backup | cut -d " " -f4)
sed -i "s|node_id = \"0x<SECP_PUBKEY>\"|node_id = \"0x$SECP_PUBKEY\"|" /home/monad/monad-bft/config/validators/validators.toml
sed -i "s|cert_pubkey = \"0x<BLS_PUBKEY>\"|cert_pubkey = \"0x$BLS_PUBKEY\"|" /home/monad/monad-bft/config/validators/validators.toml
echo "SECP: $SECP_PUBKEY"
echo "BLS: $BLS_PUBKEY"

log "Generate node record signature"
sig_out=$(monad-sign-name-record \
  --address 0.0.0.0:8000 \
  --authenticated-udp-port 8001 \
  --keystore-path /home/monad/monad-bft/config/id-secp \
  --password password \
  --self-record-seq-num 0)
node_name_val="$(hostname)"
self_address=$(printf '%s\n' "$sig_out" | grep '^self_address' | cut -d'"' -f2)
self_record_seq_num=$(printf '%s\n' "$sig_out" | grep '^self_record_seq_num' | awk '{print $3}')
self_name_record_sig=$(printf '%s\n' "$sig_out" | grep '^self_name_record_sig' | cut -d'"' -f2)
echo "$sig_out"
sed -i \
  -e "s|^node_name = \".*\"|node_name = \"$node_name_val\"|" \
  -e "s|^self_address = \".*\"|self_address = \"$self_address\"|" \
  -e "s|^self_record_seq_num = .*|self_record_seq_num = $self_record_seq_num|" \
  -e "s|^self_name_record_sig = \".*\"|self_name_record_sig = \"$self_name_record_sig\"|" \
  /home/monad/monad-bft/config/node.toml

log "Print configuration"
cat /home/monad/monad-bft/config/node.toml
cat /home/monad/monad-bft/config/validators/validators.toml

log "Prepare triedb device"
fallocate -l 100G /loopfile.img
DEVICE="/dev/loop${NODE_ID:-0}"
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

# --statesync-sq-thread-cpu 1 \

ln -s /home/monad/monad-bft monad
log "Start ledger tail"
sleep 5
while true; do
  /usr/local/bin/monad-ledger-tail | jq -C -c . || true
  sleep 1
done
