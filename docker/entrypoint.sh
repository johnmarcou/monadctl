#!/usr/bin/env bash

set -e

VAL_ID=${VAL_ID:-0}
# VAL_ID=$(hostname)
VALIDATOR_NAME="validator-$VAL_ID"
CONTAINER_IP_ADDRESS="$(hostname -i)"
TOTAL_VALIDATOR_NUMBER=${TOTAL_VALIDATOR_NUMBER:-1}
SHARED_PATH="/shared"

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
SECP_PRIVKEY=$(grep "private key" /opt/monad/backup/secp-backup | cut -d " " -f4)
BLS_PUBKEY=$(grep "public key" /opt/monad/backup/bls-backup | cut -d " " -f4)
BLS_PRIVKEY=$(grep "private key" /opt/monad/backup/bls-backup | cut -d " " -f4)

log "Generate node record signature"
sig_out=$(
  monad-sign-name-record \
    --address "$CONTAINER_IP_ADDRESS:8000" \
    --authenticated-udp-port 8001 \
    --keystore-path /home/monad/monad-bft/config/id-secp \
    --password password \
    --self-record-seq-num 0
)
echo "$sig_out"
SELF_NAME_RECORD_SIG=$(printf '%s\n' "$sig_out" | grep '^self_name_record_sig' | cut -d'"' -f2)

log "Generate peer file"
TMP_PEER_FILE="$(mktemp)"
PEER_FILE="${SHARED_PATH}/${VALIDATOR_NAME}.peer"
jq -n \
  --arg validator_name "$VALIDATOR_NAME" \
  --arg secp_pub "$SECP_PUBKEY" \
  --arg secp_priv "$SECP_PRIVKEY" \
  --arg bls_pub "$BLS_PUBKEY" \
  --arg bls_priv "$BLS_PRIVKEY" \
  --arg sig "$SELF_NAME_RECORD_SIG" \
  --arg ip "$CONTAINER_IP_ADDRESS" \
  '{
    validator_name: $validator_name,
    address: ($ip + ":8000"),
    auth_port: 8001,
    secp256k1: {
      public_key: $secp_pub,
      private_key: $secp_priv
    },
    bls: {
      public_key: $bls_pub,
      private_key: $bls_priv
    },
    self_name_record_sig: $sig
  }' >"$TMP_PEER_FILE"
cp "$TMP_PEER_FILE" "$PEER_FILE"

log "Waiting for all peers info..."
while true; do
  ready_count="$(find "$SHARED_PATH/" -maxdepth 1 -type f -name '*.peer' | wc -l | tr -d ' ')"
  if [[ "$ready_count" -ge "$TOTAL_VALIDATOR_NUMBER" ]]; then
    break
  fi
  echo "Waiting, have ${ready_count}/${TOTAL_VALIDATOR_NUMBER} ready..."
  sleep 1
done
cat "/$SHARED_PATH/"*

log "Building node.toml configuration"
# sed -i \
#   -e "s|^node_name = \".*\"|node_name = \"$VALIDATOR_NAME\"|" \
#   -e "s|^self_address = \".*\"|self_address = \"$CONTAINER_IP_ADDRESS:8000\"|" \
#   -e "s|^self_record_seq_num = .*|self_record_seq_num = 0|" \
#   -e "s|^self_name_record_sig = \".*\"|self_name_record_sig = \"$SELF_NAME_RECORD_SIG\"|" \
#   /home/monad/monad-bft/config/node.toml
#
# for f in /shared/*.peer; do
#   [[ -f "$f" ]] || continue
#   jq -r '
#     [
#       "# \(.validator_name)",
#       "[[bootstrap.peers]]",
#       "address = \"\(.address)\"",
#       "record_seq_num = \(.record_seq_num // 0)",
#       "name_record_sig = \"\(.self_name_record_sig)\"",
#       "secp256k1_pubkey = \"0x\(.secp256k1.public_key | sub("^0x"; ""))\"",
#       "auth_port = \(.auth_port // 8001)",
#       ""
#     ] | join("\n")
#   ' "$f" >>/home/monad/monad-bft/config/node.toml
# done
NODE_TOML="/home/monad/monad-bft/config/node.toml"

for f in /shared/*.peer; do
  [[ -f "$f" ]] || continue

  # Extract fields once
  PEER_VALIDATOR_NAME=$(jq -r '.validator_name' "$f")
  PEER_ADDRESS=$(jq -r '.address' "$f")
  PEER_RECORD_SEQ=$(jq -r '.record_seq_num // 0' "$f")
  PEER_SIG=$(jq -r '.self_name_record_sig' "$f")
  PEER_SECP=$(jq -r '.secp256k1.public_key' "$f")
  PEER_AUTH_PORT=$(jq -r '.auth_port // 8001' "$f")

  if [[ "$PEER_VALIDATOR_NAME" == "$VALIDATOR_NAME" ]]; then
    echo "Updating self configuration for $VALIDATOR_NAME"
    sed -i \
      -e "s|^node_name = \".*\"|node_name = \"$PEER_VALIDATOR_NAME\"|" \
      -e "s|^self_address = \".*\"|self_address = \"$PEER_ADDRESS\"|" \
      -e "s|^self_record_seq_num = .*|self_record_seq_num = ${PEER_RECORD_SEQ}|" \
      -e "s|^self_name_record_sig = \".*\"|self_name_record_sig = \"$PEER_SIG\"|" \
      "$NODE_TOML"
  fi

  cat >>"$NODE_TOML" <<EOF

# ${PEER_VALIDATOR_NAME}
[[bootstrap.peers]]
address = "${PEER_ADDRESS}"
record_seq_num = ${PEER_RECORD_SEQ}
name_record_sig = "${PEER_SIG}"
secp256k1_pubkey = "0x${PEER_SECP}"
auth_port = ${PEER_AUTH_PORT}
EOF
done

log "Building validator.toml configuration"
VALIDATORS_TOML="/home/monad/monad-bft/config/validators/validators.toml"
cat >"$VALIDATORS_TOML" <<'EOF'
[[validator_sets]]
epoch = 1
EOF

for f in /shared/*.peer; do
  [[ -f "$f" ]] || continue
  SECP_PUBKEY=$(jq -r '.secp256k1.public_key' "$f")
  BLS_PUBKEY=$(jq -r '.bls.public_key' "$f")
  cat >>"$VALIDATORS_TOML" <<EOF

[[validator_sets.validators]]
node_id = "0x${SECP_PUBKEY}"
stake = 1
cert_pubkey = "0x${BLS_PUBKEY}"
EOF
done

log "Print configuration"
echo ">> node.toml"
cat /home/monad/monad-bft/config/node.toml
echo ">> validators.toml"
cat /home/monad/monad-bft/config/validators/validators.toml

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

# --statesync-sq-thread-cpu 1 \

sleep 5
log "Start ledger tail"
ln -s /home/monad/monad-bft monad
while true; do
  /usr/local/bin/monad-ledger-tail | jq -C -c . || true
  sleep 1
done
