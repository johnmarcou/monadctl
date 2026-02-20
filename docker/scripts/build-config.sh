#!/usr/bin/env bash

set -e

SHARED_PATH="/shared"
VAL_ID=${VAL_ID:-1}
VALIDATOR_NAME="validator-$VAL_ID"

log "Waiting for all peers info..."
while true; do
  ready_count="$(find "$SHARED_PATH/" -maxdepth 1 -type f -name '*.peer' | wc -l | tr -d ' ')"
  if [[ "$ready_count" -ge "$TOTAL_VALIDATOR_NUMBER" ]]; then
    break
  fi
  echo "Waiting, have ${ready_count}/${TOTAL_VALIDATOR_NUMBER} ready..."
  sleep 1
done

log "Building node.toml configuration"
for f in /shared/*.peer; do
  [[ -f "$f" ]] || continue

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
      /home/monad/monad-bft/config/node.toml
  fi

  cat >>/home/monad/monad-bft/config/node.toml <<EOF

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
mkdir -p /home/monad/monad-bft/config/validators/
cat >/home/monad/monad-bft/config/validators/validators.toml <<'EOF'
[[validator_sets]]
epoch = 1
EOF

for f in /shared/*.peer; do
  [[ -f "$f" ]] || continue
  SECP_PUBKEY=$(jq -r '.secp256k1.public_key' "$f")
  BLS_PUBKEY=$(jq -r '.bls.public_key' "$f")
  cat >>/home/monad/monad-bft/config/validators/validators.toml <<EOF

[[validator_sets.validators]]
node_id = "0x${SECP_PUBKEY}"
stake = 1
cert_pubkey = "0x${BLS_PUBKEY}"
EOF
done

log "Print configuration"
echo
echo ">> node.toml"
cat /home/monad/monad-bft/config/node.toml
echo
echo ">> validators.toml"
cat /home/monad/monad-bft/config/validators/validators.toml
