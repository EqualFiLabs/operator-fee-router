#!/usr/bin/env bash
set -euo pipefail

: "${ROBINHOOD_TESTNET:?ROBINHOOD_TESTNET must be set}"

cast_bin=${CAST_BIN:-cast}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
manifest="$repo_root/deployments/46630/operator-fee-router-rehearsal.json"

assert_equal() {
    local actual=$1
    local expected=$2
    local label=$3
    if [[ ${actual,,} != "${expected,,}" ]]; then
        printf '%s mismatch: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_code_hash() {
    local address=$1
    local expected=$2
    local label=$3
    local code
    code=$($cast_bin code "$address" --rpc-url "$ROBINHOOD_TESTNET")
    [[ $code != "0x" ]] || {
        printf '%s has no runtime bytecode\n' "$label" >&2
        exit 1
    }
    assert_equal "$($cast_bin keccak "$code")" "$expected" "$label runtime hash"
}

assert_receipt() {
    local transaction_hash=$1
    local expected_block=${2:-}
    local expected_gas=${3:-}
    local receipt
    receipt=$($cast_bin receipt "$transaction_hash" --rpc-url "$ROBINHOOD_TESTNET" --json)
    assert_equal "$(jq -r '.status' <<<"$receipt")" "0x1" "transaction $transaction_hash status"
    if [[ -n $expected_block ]]; then
        assert_equal \
            "$($cast_bin to-dec "$(jq -r '.blockNumber' <<<"$receipt")")" \
            "$expected_block" \
            "transaction $transaction_hash block"
    fi
    if [[ -n $expected_gas ]]; then
        assert_equal \
            "$($cast_bin to-dec "$(jq -r '.gasUsed' <<<"$receipt")")" \
            "$expected_gas" \
            "transaction $transaction_hash gas"
    fi
}

jq empty "$manifest"
chain_id=$($cast_bin chain-id --rpc-url "$ROBINHOOD_TESTNET")
assert_equal "$chain_id" "$(jq -r '.network.chainId' "$manifest")" "chain ID"

while IFS= read -r encoded_contract; do
    contract=$(base64 --decode <<<"$encoded_contract")
    assert_code_hash \
        "$(jq -r '.address' <<<"$contract")" \
        "$(jq -r '.runtimeKeccak256' <<<"$contract")" \
        "$(jq -r '.label' <<<"$contract")"
done < <(
    jq -r '
        [
            (.staticsGenesisReplica.contracts.operatorCollection + {label: "Operator collection"}),
            (.staticsGenesisReplica.contracts.activationRegistry + {label: "activation registry"}),
            (.staticsGenesisReplica.contracts.operatorVault + {label: "Operator vault"}),
            (.deployment.testnetAdmin + {label: "testnet Router admin"}),
            (.deployment.router + {label: "Operator Fee Router"}),
            (.configuration.rewardAssets[] | . + {label: ("reward asset " + .symbol)})
        ][] | @base64
    ' "$manifest"
)

admin=$(jq -r '.deployment.testnetAdmin.address' "$manifest")
router=$(jq -r '.deployment.router.address' "$manifest")
assert_equal \
    "$($cast_bin call "$admin" 'owner()(address)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.deployment.deployer' "$manifest")" \
    "testnet Router admin owner"
assert_equal \
    "$($cast_bin call "$admin" 'router()(address)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "$router" \
    "testnet Router admin binding"

for field in operatorCollection activationRegistry operatorVault routerTimelock; do
    case $field in
        operatorCollection)
            expected=$(jq -r '.deployment.router.constructorArguments.operatorCollection' "$manifest")
            ;;
        activationRegistry)
            expected=$(jq -r '.deployment.router.constructorArguments.activationRegistry' "$manifest")
            ;;
        operatorVault)
            expected=$(jq -r '.deployment.router.constructorArguments.operatorVault' "$manifest")
            ;;
        routerTimelock)
            expected=$(jq -r '.deployment.router.constructorArguments.routerTimelock' "$manifest")
            ;;
    esac
    assert_equal \
        "$($cast_bin call "$router" "$field()(address)" --rpc-url "$ROBINHOOD_TESTNET")" \
        "$expected" \
        "Router $field"
done

assert_equal \
    "$($cast_bin call "$router" 'bootstrapFinalized()(bool)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.configuration.finalState.bootstrapFinalized' "$manifest")" \
    "Router bootstrap state"
assert_equal \
    "$($cast_bin call "$router" 'nextOperatorId()(uint256)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.configuration.finalState.nextOperatorId' "$manifest")" \
    "Router bootstrap cursor"
assert_equal \
    "$($cast_bin call "$router" 'totalEffectiveWeight()(uint256)' --rpc-url "$ROBINHOOD_TESTNET" | awk '{print $1}')" \
    "$(jq -r '.configuration.finalState.totalEffectiveWeight' "$manifest")" \
    "Router effective weight"
assert_equal \
    "$($cast_bin call "$router" 'rewardAssetCount()(uint256)' --rpc-url "$ROBINHOOD_TESTNET")" \
    "$(jq -r '.configuration.finalState.rewardAssetCount' "$manifest")" \
    "Router reward asset count"

while IFS= read -r encoded_asset; do
    asset=$(base64 --decode <<<"$encoded_asset")
    address=$(jq -r '.address' <<<"$asset")
    symbol=$(jq -r '.symbol' <<<"$asset")
    assert_equal \
        "$($cast_bin call "$router" 'isRewardAsset(address)(bool)' "$address" --rpc-url "$ROBINHOOD_TESTNET")" \
        "true" \
        "$symbol registration"
    assert_equal \
        "$($cast_bin call "$router" 'rewardAssetEnabled(address)(bool)' "$address" --rpc-url "$ROBINHOOD_TESTNET")" \
        "true" \
        "$symbol enabled state"
done < <(jq -r '.configuration.rewardAssets[] | @base64' "$manifest")

while IFS= read -r encoded_transaction; do
    transaction=$(base64 --decode <<<"$encoded_transaction")
    assert_receipt \
        "$(jq -r '.transactionHash' <<<"$transaction")" \
        "$(jq -r '.blockNumber' <<<"$transaction")" \
        "$(jq -r '.gasUsed' <<<"$transaction")"
done < <(
    jq -r '
        .deployment.testnetAdmin,
        .deployment.router,
        .deployment.adminBinding,
        .configuration.finalization,
        (.configuration.rewardAssets[] | {
            transactionHash: .registrationTransactionHash,
            blockNumber,
            gasUsed
        })
        | @base64
    ' "$manifest"
)

mapfile -t bootstrap_transactions < <(jq -r '.configuration.bootstrap.transactionHashes[]' "$manifest")
assert_equal \
    "${#bootstrap_transactions[@]}" \
    "$(jq -r '.configuration.bootstrap.transactionCount' "$manifest")" \
    "bootstrap transaction count"
for transaction_hash in "${bootstrap_transactions[@]}"; do
    assert_receipt "$transaction_hash"
done

first_receipt=$($cast_bin receipt "${bootstrap_transactions[0]}" --rpc-url "$ROBINHOOD_TESTNET" --json)
last_index=$((${#bootstrap_transactions[@]} - 1))
last_receipt=$($cast_bin receipt "${bootstrap_transactions[$last_index]}" --rpc-url "$ROBINHOOD_TESTNET" --json)
assert_equal \
    "$($cast_bin to-dec "$(jq -r '.blockNumber' <<<"$first_receipt")")" \
    "$(jq -r '.configuration.bootstrap.firstBlock' "$manifest")" \
    "first bootstrap block"
assert_equal \
    "$($cast_bin to-dec "$(jq -r '.blockNumber' <<<"$last_receipt")")" \
    "$(jq -r '.configuration.bootstrap.lastBlock' "$manifest")" \
    "last bootstrap block"

printf 'Operator Fee Router rehearsal manifest validated on chain %s\n' "$chain_id"
