#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    printf 'Usage: %s TIMELOCK_TX ROUTER_TX [CANDIDATE_JSON]\n' "$0" >&2
    exit 1
fi

: "${ROBINHOOD_MAINNET:?Load the private RPC configuration first}"
cast_bin=${CAST_BIN:-cast}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
candidate=${3:-"$script_dir/../deployments/4663/operator-fee-router.candidate.json"}
destination="$(dirname -- "$candidate")/operator-fee-router.json"
temporary=$(mktemp "$(dirname -- "$candidate")/.router-manifest-XXXXXX")
rpc_error=$(mktemp)
trap 'rm -f -- "$temporary" "$rpc_error"' EXIT

rpc() {
    if ! "$cast_bin" "$@" --rpc-url "$ROBINHOOD_MAINNET" 2>"$rpc_error"; then
        printf 'RPC command failed: %s (endpoint details withheld)\n' "$1" >&2
        return 1
    fi
}

assert_equal() {
    if [[ ${1,,} != "${2,,}" ]]; then
        printf '%s mismatch\n' "$3" >&2
        exit 1
    fi
}

# Freeze the candidate used by every check and publish only after all checks succeed.
cp -- "$candidate" "$temporary"
jq -e '
    .chainId == 4663 and .timelockDelay == 86400 and
    ([.router, .timelock, .operatorCollection, .activationRegistry, .operatorVault, .timelockProposer] |
        all(type == "string" and test("^0x[0-9a-fA-F]{40}$") and . != "0x0000000000000000000000000000000000000000")) and
    .timelockExecutor == "0x0000000000000000000000000000000000000000" and
    ([.routerCodehash, .timelockCodehash, .routerCreationCodehash, .timelockCreationCodehash] |
        all(type == "string" and test("^0x[0-9a-fA-F]{64}$")))
' "$temporary" >/dev/null
assert_equal "$(rpc chain-id)" 4663 'chain ID'

receipts=()
for kind in timelock router; do
    if [[ $kind == timelock ]]; then tx=$1; else tx=$2; fi
    [[ $tx =~ ^0x[0-9a-fA-F]{64}$ ]] || { printf 'Invalid transaction hash\n' >&2; exit 1; }
    address=$(jq -r --arg kind "$kind" '.[$kind]' "$temporary")
    receipt=$(rpc receipt "$tx" --json)
    jq -e '.status == "0x1" and .blockNumber != null and .blockHash != null' <<<"$receipt" >/dev/null
    assert_equal "$(jq -r '.transactionHash' <<<"$receipt")" "$tx" "$kind transaction"
    assert_equal "$(jq -r '.contractAddress' <<<"$receipt")" "$address" "$kind deployment address"
    transaction=$(rpc tx "$tx" --json)
    jq -e '.to == null and (.input | type == "string" and test("^0x[0-9a-fA-F]+$"))' <<<"$transaction" >/dev/null
    creation_hash=$("$cast_bin" keccak "$(jq -r '.input' <<<"$transaction")")
    assert_equal "$creation_hash" \
        "$(jq -r --arg kind "$kind" '.[$kind + "CreationCodehash"]' "$temporary")" "$kind creation input"
    code=$(rpc code "$address")
    [[ $code != 0x ]] || { printf '%s has no deployed code\n' "$kind" >&2; exit 1; }
    assert_equal "$("$cast_bin" keccak "$code")" \
        "$(jq -r --arg kind "$kind" '.[$kind + "Codehash"]' "$temporary")" "$kind runtime hash"
    receipts+=("$receipt")
done

router=$(jq -r '.router' "$temporary")
timelock=$(jq -r '.timelock' "$temporary")
proposer=$(jq -r '.timelockProposer' "$temporary")
for field in operatorCollection activationRegistry operatorVault routerTimelock; do
    if [[ $field == routerTimelock ]]; then expected=$timelock; else expected=$(jq -r --arg field "$field" '.[$field]' "$temporary"); fi
    assert_equal "$(rpc call "$router" "$field()(address)")" "$expected" "$field"
done
assert_equal "$(rpc call "$timelock" 'getMinDelay()(uint256)' | awk '{print $1}')" 86400 'timelock delay'
for role in PROPOSER_ROLE CANCELLER_ROLE EXECUTOR_ROLE DEFAULT_ADMIN_ROLE; do
    role_id=$(rpc call "$timelock" "$role()(bytes32)")
    case $role in
        PROPOSER_ROLE|CANCELLER_ROLE) account=$proposer ;;
        EXECUTOR_ROLE) account=0x0000000000000000000000000000000000000000 ;;
        DEFAULT_ADMIN_ROLE) account=$timelock ;;
    esac
    assert_equal "$(rpc call "$timelock" 'hasRole(bytes32,address)(bool)' "$role_id" "$account")" true "$role"
done

json=$(jq --argjson timelockReceipt "${receipts[0]}" --argjson routerReceipt "${receipts[1]}" '
    . + {deploymentReceipts: {
        timelock: ($timelockReceipt | {transactionHash, blockNumber, blockHash, contractAddress, status}),
        router: ($routerReceipt | {transactionHash, blockNumber, blockHash, contractAddress, status})
    }}
' "$temporary")
printf '%s\n' "$json" > "$temporary"
mv -- "$temporary" "$destination"
printf 'Confirmed deployment manifest: %s\n' "$destination"
