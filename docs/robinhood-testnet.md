# Robinhood Testnet Router Rehearsal

This document archives the disposable Operator Fee Router used by the Statics Lottery release
rehearsal on Robinhood Testnet chain `46630`. It is historical integration evidence, not a
production deployment recommendation.

## Composition and provenance

The rehearsal reused the existing Statics Genesis replica rather than replaying its launch. The
Router constructor was bound to that replica's Operator collection, activation registry, and
Operator vault. The exact Statics source and deployment-manifest revisions, dependency addresses,
and runtime hashes are pinned in
[`operator-fee-router-rehearsal.json`](../deployments/46630/operator-fee-router-rehearsal.json).

The rehearsal freshly deployed:

- the production `OperatorFeeRouter` implementation from commit
  `f98a17780cb250ce28f446ab54eb078512fb2e0b`; and
- the testnet-only [`TestnetRouterAdmin`](../src/testnet/TestnetRouterAdmin.sol).

The admin replaces the production 24-hour timelock only on this disposable deployment. It is
chain-guarded to `46630`, has one immutable owner, can bind exactly one Router, and forwards only
reward-asset registration and enablement calls. It cannot be reused as a production governance
model.

The recovered admin source compiles with the recorded Solidity 0.8.33, Cancun, optimizer-200, and
metadata-free settings to the deployed runtime hash. The focused unit test keeps that historical
hash as a regression assertion.

## Deployment and configuration ceremony

[`DeployTestnetRouter.s.sol`](../script/DeployTestnetRouter.s.sol) checks the chain, expected
broadcaster, and Genesis dependency hashes before deploying and binding the admin and Router.
Deployment addresses remain nonce-dependent; the script does not claim CREATE2 determinism.

[`ConfigureTestnetRouter.s.sol`](../script/ConfigureTestnetRouter.s.sol) resumes permissionless
bootstrap in batches of 100, finalizes only after Operators 1 through 5,555 are initialized, and
registers the pinned WETH and STATICS contracts through the admin. The manifest records every
bootstrap transaction plus the finalization and registration receipts.

The historical final state is:

| Field | Value |
|---|---:|
| Initialized Operator IDs | 1 through 5,555 |
| Next Operator ID | 5,556 |
| Total effective weight | 5,550,000 |
| Enabled reward assets | WETH and STATICS |

The Statics Lottery lifecycle later disabled WETH deposits through the testnet admin, proved that
failed Router funding preserved the Lottery liability, re-enabled WETH, and successfully funded
both WETH and STATICS reward books. Those transaction-level results are pinned in the linked
`EqualFiLabs/fiddy` lifecycle manifest.

## Validation

Load the intended Robinhood Testnet RPC without printing it, then run the read-only state and
bytecode validator:

```bash
forge script script/ValidateRobinhoodTestnetRouter.s.sol:ValidateRobinhoodTestnetRouter \
  --rpc-url "$ROBINHOOD_TESTNET"
```

The validator checks the chain ID, every pinned runtime hash, admin ownership and binding, Router
constructor dependencies, completed bootstrap, effective weight, and both reward assets. It does
not broadcast a transaction.

The companion receipt validator checks the Router-owned manifest, every recorded successful
transaction, the bootstrap block range, and the same live code and state:

```bash
script/validate-robinhood-testnet-router.sh
```

Explorer source verification was intentionally waived because this is a throwaway testnet
deployment. Runtime hashes, receipts, source/toolchain pins, and live-state validation remain the
authoritative evidence.
