#!/usr/bin/env bash

set -e

generate-keys.sh
build-config.sh
start-node.sh
