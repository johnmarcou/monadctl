#!/usr/bin/env bash

set -e

VAL_ID=${VAL_ID:-1}
VALIDATOR_NAME="validator-$VAL_ID"
CONTAINER_IP_ADDRESS="$(hostname -i)"
SHARED_PATH="/shared"
PEER_FILE="${SHARED_PATH}/${VALIDATOR_NAME}.peer"

[[ -f "$PEER_FILE" ]] && {
  echo "Already existing peer file: $PEER_FILE" >&2
  exit 0
}

log "Generate keys"
monad-keystore create \
  --key-type secp \
  --keystore-path /home/monad/monad-bft/config/id-secp \
  --password password >/opt/monad/backup/secp-backup

monad-keystore create \
  --key-type bls \
  --keystore-path /home/monad/monad-bft/config/id-bls \
  --password password >/opt/monad/backup/bls-backup

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

log "Generate peer file"
TMP_PEER_FILE="$(mktemp)"
SECP_PUBKEY=$(grep "public key" /opt/monad/backup/secp-backup | cut -d " " -f4)
SECP_PRIVKEY=$(grep "private key" /opt/monad/backup/secp-backup | cut -d " " -f4)
BLS_PUBKEY=$(grep "public key" /opt/monad/backup/bls-backup | cut -d " " -f4)
BLS_PRIVKEY=$(grep "private key" /opt/monad/backup/bls-backup | cut -d " " -f4)
SELF_NAME_RECORD_SIG=$(printf '%s\n' "$sig_out" | grep '^self_name_record_sig' | cut -d'"' -f2)

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

mkdir -p "$SHARED_PATH"
cp "$TMP_PEER_FILE" "$PEER_FILE"
cat "$PEER_FILE"
