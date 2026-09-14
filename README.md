# Operator Fee Router

Standalone, multiplier-weighted ERC-20 reward routing for Statics Operator NFTs.

The router is intentionally independent from the Statics Diamond. It reads current ownership and activation state from
the canonical Operator contracts, maintains its own lazy-synchronized accounting, and never participates in Operator
transfer or activation callbacks.

The normative design is tracked in [issue #1](https://github.com/EqualFiLabs/operator-fee-router/issues/1).

See [the architecture document](docs/architecture.md) for the trust boundary, synchronization rules, forfeiture
accounting, and integration interface.

## Development

```bash
git submodule update --init --recursive
forge build
forge test
```

Solidity is pinned to 0.8.33 with the Cancun EVM target.

## Reward integration

After the dedicated 24-hour router timelock registers an ERC-20 asset, contributors need no allowlist:

```solidity
IERC20(asset).approve(address(router), amount);
router.addRewards(asset, amount);
```

V1 supports exact-transfer, non-rebasing ERC-20 assets. Reward assets should not have mutable transfer fees, rebases,
pauses, blocklists, or upgrade authority that can change transfer behavior after funding. Each asset is capped at
`type(uint96).max` outstanding base units to keep the cumulative RAY index far from the `uint256` arithmetic boundary.
Wrap native revenue before adding it.

## Robinhood deployment

Deployment is deliberately split from bootstrap:

```bash
forge script script/DeployOperatorFeeRouter.s.sol:DeployOperatorFeeRouter \
  --rpc-url "$ROBINHOOD_MAINNET" --broadcast

forge script script/BootstrapOperatorFeeRouter.s.sol:BootstrapOperatorFeeRouter \
  --rpc-url "$ROBINHOOD_MAINNET" --broadcast
```

The deployment requires `OPERATOR_ROUTER_DEPLOYER_PRIVATE_KEY` and `OPERATOR_ROUTER_TIMELOCK_PROPOSER`. The proposer
should be a verified multisig or Governor; execution is intentionally open. Never commit private keys or RPC endpoints.
The script is chain-guarded to Robinhood chain ID 4663 and writes an initial address/code-hash manifest under
`deployments/4663/`. Final deployment evidence must be completed from confirmed transaction receipts because EVM
`block.number` is not the Robinhood L2 inclusion height.

Verify each deployed contract through Robinhood Blockscout using `forge verify-contract` with `--chain-id 4663`,
`--verifier blockscout`, and `--verifier-url https://robinhoodchain.blockscout.com/api/`.

## Validation

Foundry provides unit, fuzz, invariant, gas, and pinned-fork suites. Halmos harnesses run in GitHub Actions, and the
Certora specifications can be submitted with `scripts/run-certora.sh`. Completed formal-verification results and model
bounds are recorded in [the formal results](docs/formal-verification-results.md).

The full pinned 5,555-Operator lifecycle is enabled with `RUN_FULL_ROUTER_FORK=true` and requires
`ROBINHOOD_MAINNET`. Without the RPC, fork tests report as skipped rather than passing silently.
