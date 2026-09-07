# Operator Fee Router

Standalone, multiplier-weighted ERC-20 reward routing for Statics Operator NFTs.

The router is intentionally independent from the Statics Diamond. It reads current ownership and activation state from
the canonical Operator contracts, maintains its own lazy-synchronized accounting, and never participates in Operator
transfer or activation callbacks.

The normative design is tracked in [issue #1](https://github.com/hooftly/operator-fee-router/issues/1).

## Development

```bash
git submodule update --init --recursive
forge build
forge test
```

Solidity is pinned to 0.8.33 with the Cancun EVM target.
