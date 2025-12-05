#!/usr/bin/env bash

# setup for online version:
#
# install -m 0755 <(curl https://raw.githubusercontent.com/johnmarcou/monadctl/refs/heads/main/run-monadctl.sh) /usr/local/bin/monadctl
#

set -euo pipefail

API_URL="https://api.github.com/repos/johnmarcou/monadctl/contents/monadctl?ref=main"

# Fetch base64 content
CONTENT=$(curl -fsSL "$API_URL" | jq -r '.content' | tr -d '\n')

# Decode + execute
echo "$CONTENT" | base64 --decode | bash -s -- "$@"
