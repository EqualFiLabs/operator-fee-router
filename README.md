# Operator Fee Router

Standalone, multiplier-weighted ERC-20 reward routing for Statics Operator NFTs.

The router is intentionally independent from the Statics Diamond. It reads current ownership and activation state from
the canonical Operator contracts, maintains its own lazy-synchronized accounting, and never participates in Operator
transfer or activation callbacks.

See [the architecture document](docs/architecture.md) for the trust boundary, synchronization rules, forfeiture
accounting, and integration interface.

Deployment evidence is indexed by network under [`deployments/`](deployments/). The disposable Robinhood Testnet
Router used by the Statics Lottery is documented separately in
[`docs/robinhood-testnet.md`](docs/robinhood-testnet.md); it does not replace the production timelock model below.

## Development

```bash
git submodule update --init --recursive
forge build
forge test
```

Solidity is pinned to 0.8.33 with the Cancun EVM target.

## Reward integration

After a proposer of the dedicated router timelock registers an ERC-20 asset directly, contributors need no allowlist:

```solidity
IERC20(asset).approve(address(router), amount);
router.addRewards(asset, amount);
```

V1 supports exact-transfer, non-rebasing ERC-20 assets with at most 18 decimals, including upgradeable tokens.
Registration requires a valid `decimals()` response of 0 through 18. Reward assets should not have mutable
transfer fees, rebases, pauses, or blocklists. Each asset is capped at
`type(uint96).max` outstanding base units to keep the cumulative RAY index far from the `uint256` arithmetic boundary.
Wrap native revenue before adding it.

## Reward asset lifecycle

The governance Safe uses its existing timelock proposer role to register assets and toggle deposits directly. The
timelock itself can also perform these actions. Timelocked proposer grants and revocations also grant and revoke
cancellation authority. A proposer can renounce its own role immediately, which also removes its cancellation
authority; the sole proposer must retain its role until a successor has been granted authority.

- **Active:** deposits, claims, and settlement are available.
- **Claim-only:** `setRewardAssetEnabled(asset, false)` stops deposits while claims, settlement, and forfeiture
  redistribution continue. This state can last indefinitely, and the proposer can re-enable deposits.
- **Deregistered:** the timelock executes `deregisterRewardAsset(asset)` on a claim-only asset. All remaining reward
  liabilities expire, including unpaid rewards, queued forfeitures, and rounding dust. The token address cannot be
  registered again. Removal frees a slot and removes the asset from synchronization work.

To retire an asset, announce the intended claim cutoff, disable deposits, and schedule deregistration through the
existing timelock. Claims remain available until the deregistration transaction executes, even if the operation has
already become ready. There is no separate onchain deadline or additional waiting period. Cancel superseded operations
through the timelock; re-enabling deposits does not cancel a scheduled operation, although execution requires deposits
to be disabled again.

Deregistration moves no tokens. The remaining balance becomes surplus, recoverable only through a timelocked
`recoverSurplus` operation. Recovery retains the existing scheduling and batching rules, with no new post-deregistration
lock. Historical raw accounting records remain readable but are no longer claimable.

## Robinhood deployment

Deployment is deliberately split from bootstrap. First, deploy the router and its timelock:

```bash
forge script script/DeployOperatorFeeRouter.s.sol:DeployOperatorFeeRouter \
  --rpc-url "$ROBINHOOD_MAINNET" --broadcast
```

The simulation writes `deployments/4663/operator-fee-router.candidate.json`; it is not evidence of deployment.
After both deployment transactions confirm, use their transaction hashes to publish the final manifest:

```bash
bash script/finalize-router-deployment.sh "<timelock-transaction-hash>" "<router-transaction-hash>"
```

This command reads the network and checks successful creation receipts, contract addresses, creation inputs (including
constructor arguments), runtime code hashes, dependencies, delay, and governance roles before writing
`deployments/4663/operator-fee-router.json`. A failed check
leaves any previous final manifest intact. Load `ROBINHOOD_MAINNET` from the private RPC configuration first.

Use the confirmed `router` address from that final manifest below, then initialize the router's records for all
5,555 existing Operators. The bootstrap script deploys no contracts and finalizes bootstrap to enable reward deposits
for registered assets.

```bash
export OPERATOR_FEE_ROUTER="<deployed-router-address>"
forge script script/BootstrapOperatorFeeRouter.s.sol:BootstrapOperatorFeeRouter \
  --rpc-url "$ROBINHOOD_MAINNET" --broadcast
```

The deployment requires `OPERATOR_ROUTER_DEPLOYER_PRIVATE_KEY` and `OPERATOR_ROUTER_TIMELOCK_PROPOSER`. The proposer
should be a verified multisig or Governor; execution is intentionally open. Never commit private keys or RPC endpoints.
The script is chain-guarded to Robinhood chain ID 4663. Final deployment evidence uses confirmed transaction receipts
because EVM `block.number` is not the Robinhood L2 inclusion height.

Verify each deployed contract through Robinhood Blockscout using `forge verify-contract` with `--chain-id 4663`,
`--verifier blockscout`, and `--verifier-url https://robinhoodchain.blockscout.com/api/`.

## Validation

Foundry provides unit, fuzz, invariant, gas, and pinned-fork suites. GitHub Actions runs the timelock and sync Halmos
harnesses. The [central formal verification summary](docs/formal-verification-results.md) documents the verification
commands, proof coverage, model bounds, and recorded outcomes for Halmos and Certora. Generated proof outputs stay
outside version control.

The full pinned 5,555-Operator lifecycle is enabled with `RUN_FULL_ROUTER_FORK=true` and requires
`ROBINHOOD_MAINNET`. Without the RPC, fork tests report as skipped rather than passing silently.

For receipt-backed Anvil and cast lifecycle, hostile-asset and stateful campaigns, see the
[mainnet fork rehearsal](scripts/mainnet-rehearsal/README.md). Generated evidence remains private.
