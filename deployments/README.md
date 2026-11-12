# Deployment Evidence

Deployment records are grouped by chain ID and pin the source revision, toolchain, runtime bytecode,
transactions, dependency provenance, and validation boundary for each deployment.

| Network | Chain ID | Deployment | Status |
|---|---:|---|---|
| Robinhood Mainnet | 4663 | [Operator Fee Router](4663/README.md) | Deployed; bootstrap finalized; USDG and WETH enabled |
| Robinhood Testnet | 46630 | [Lottery integration rehearsal](46630/operator-fee-router-rehearsal.json) | Disposable historical evidence |

The Robinhood Testnet deployment replaces the production timelock with a chain-guarded testnet admin.
See [the composition and validation notes](../docs/robinhood-testnet.md) before reusing any part of it.
