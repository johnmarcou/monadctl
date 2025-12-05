#!/usr/bin/env bash

# setup for online version:
#
# install -m 0755 <(curl https://raw.githubusercontent.com/johnmarcou/monadctl/refs/heads/main/run-monadctl.sh) /usr/local/bin/monadctl
#

set -euo pipefail

REMOTE_URL="https://raw.githubusercontent.com/johnmarcou/monadctl/refs/heads/main/monadctl.sh"

curl -fsSL "$REMOTE_URL" | bash -s -- "$@"
