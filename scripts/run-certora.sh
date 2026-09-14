#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-all}"
CERTORA_BIN="${CERTORA_BIN:-certoraRun}"

if [[ -z "${CERTORAKEY:-}" ]]; then
  printf 'CERTORAKEY must be set\n' >&2
  exit 1
fi

cd "$ROOT"

run_config() {
  "$CERTORA_BIN" "$ROOT/certora/conf/$1.conf"
}

case "$TARGET" in
  accounting)
    run_config OperatorFeeRouterAccounting
    ;;
  sync)
    run_config OperatorFeeRouterSync
    ;;
  all)
    run_config OperatorFeeRouterAccounting
    run_config OperatorFeeRouterSync
    ;;
  *)
    printf 'unknown Certora target: %s\n' "$TARGET" >&2
    exit 2
    ;;
esac
