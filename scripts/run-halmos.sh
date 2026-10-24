#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG_DIR="${FORMAL_LOG_DIR:-$ROOT/.formal-results/$(git rev-parse --short HEAD)-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$LOG_DIR"
for contract in OperatorFeeRouterTimelockHalmosTest OperatorSyncHalmosTest RouterLifecycleHalmosTest; do
  case "$contract" in
    OperatorFeeRouterTimelockHalmosTest) expected=5 ;;
    OperatorSyncHalmosTest) expected=4 ;;
    RouterLifecycleHalmosTest) expected=23 ;;
  esac
  log="$LOG_DIR/$contract.log"
  halmos --contract "$contract" --loop 4 --solver-timeout-assertion 2m --panic-error-codes '*' 2>&1 | tee "$log"
  # Halmos can exit zero even when loop-bound warnings leave unexplored paths.
  if grep -Eq 'WARNING|ERROR|\[FAIL\]' "$log" ||
    ! grep -Fq "Symbolic test result: $expected passed; 0 failed;" "$log"; then
    printf 'Incomplete or failed proof; inspect %s\n' "$log" >&2
    exit 1
  fi
done
