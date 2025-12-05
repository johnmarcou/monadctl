#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
monadctl – minimal control tool

Usage:
  monadctl status
  monadctl init
  monadctl start
  monadctl stop
  monadctl restart
EOF
}

cmd_status() {
  echo status
}

cmd_start() {
  systemctl start monad-bft monad-execution monad-rpc
}

cmd_stop() {
  systemctl stop monad-bft monad-execution monad-rpc
}

cmd_restart() {
  systemctl restart monad-bft monad-execution monad-rpc
}

main() {
  case "${1:-}" in
  status) cmd_status ;;
  init) cmd_init ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  restart) cmd_restart ;;
  *) usage ;;
  esac
}

main "$@"
