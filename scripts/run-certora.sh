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
  economic)
    run_config OperatorFeeRouterEconomic
    ;;
  conservation)
    run_config OperatorFeeRouterConservation
    ;;
  math)
    run_config IndexMath
    ;;
  settlement)
    run_config SettlementMath
    ;;
  all)
    run_config IndexMath
    run_config SettlementMath
    run_config OperatorFeeRouterAccounting
    run_config OperatorFeeRouterConservation
    run_config OperatorFeeRouterSync
    run_config OperatorFeeRouterEconomic
    ;;
  *)
    printf 'unknown Certora target: %s\n' "$TARGET" >&2
    exit 2
    ;;
esac
