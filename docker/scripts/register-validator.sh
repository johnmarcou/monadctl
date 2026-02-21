#!/usr/bin/env bash

set -euo pipefail

PEERS_PATH="/shared/peers"
AUTH="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
REGISTER_AMOUNT="100000"
DELEGATE_AMOUNT="10000000"

log "Staking contract registration"
if [[ "${VAL_ID:-1}" != "1" ]]; then
  echo "VAL_ID is not 1, skipping."
  exit 0
fi

pushd /home/monad/monad-bft/config/staking/ >/dev/null

for PEER_FILE in "$PEERS_PATH"/*.peer; do
  [ -f "$PEER_FILE" ] || continue

  VALIDATOR_NAME="$(basename "$PEER_FILE" .peer)"
  echo "Processing $VALIDATOR_NAME"

  SECP="$(jq -r '.secp256k1.private_key' "$PEER_FILE")"
  BLS="$(jq -r '.bls.private_key' "$PEER_FILE")"

  echo "Registering validator (amount: $REGISTER_AMOUNT)..."
  OUTPUT="$(
    yes y | staking-cli add-validator \
      --secp-privkey "$SECP" \
      --bls-privkey "$BLS" \
      --amount "$REGISTER_AMOUNT" \
      --auth-address "$AUTH"
  )" || true

  echo "$OUTPUT"

  VAL_STAKING_ID="$(echo "$OUTPUT" | grep -oE 'ID: [0-9]+' | awk '{print $2}')"

  echo "Delegating stake (amount: $DELEGATE_AMOUNT)..."
  staking-cli delegate \
    --validator-id "$VAL_STAKING_ID" \
    --amount "$DELEGATE_AMOUNT"

  echo
  staking-cli query validator --validator-id "$VAL_STAKING_ID"
  echo
done

log "Final execution validator-set"
staking-cli query epoch
staking-cli query validator-set --type execution

popd >/dev/null
