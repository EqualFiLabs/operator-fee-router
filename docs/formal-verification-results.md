# Formal verification results

Results recorded on 2026-09-07 for the production contracts and formal inputs committed with this implementation.

## Halmos 0.3.3

Foundry 1.7.1 compiled the harnesses. Every Solidity panic code was treated as a proof failure.

| Harness | Properties | Paths | Result |
| --- | ---: | ---: | --- |
| `OperatorFeeRouterTimelockHalmosTest` | 1 | 2 | Pass |
| `OperatorSyncHalmosTest` | 4 | 35 | Pass |
| **Total** | **5** | **37** | **Pass** |

The properties cover the 24-hour minimum timelock delay, unchanged-snapshot no-op behavior, prospective multiplier
activation, lower-multiplier transfer semantics, owner-mismatch transfer semantics, and exact installed-weight deltas.

## Certora Prover 8.18.0

### Accounting and asset isolation

[Hosted report](https://prover.certora.com/output/8471858/0646e7ca6696463bbb13b19965afd98a)

All eight selected properties passed without violation or timeout:

- `ghostLedgersMatchStorage`
- `liabilityEqualsAddedMinusClaimed`
- `rewardATokenSolvency`
- `rewardBTokenSolvency`
- `addRewardsHasExactDeltas`
- `claimHasExactDeltas`
- `recoverSurplusPreservesAccounting`
- `rewardAssetsAreIsolated`

### Synchronization and forfeiture

[Hosted report](https://prover.certora.com/output/8471858/31ea86eafeec4575bb712adcd2d347e0)

All three selected rules passed without violation or timeout:

- `activationSettlesAtOldWeight`
- `lowerMultiplierUsesTransferSemantics`
- `ownerMismatchForfeitureConservesScaledValue`

Both jobs finished with prover exit code zero and basic rule-sanity checks enabled.

## Model bounds

- The accounting harness inherits the production Router and uses three Operators with two linked exact-transfer tokens.
- Accounting invariants apply to the finalized operational state after bootstrap.
- The exact-token model covers successful token movement; allowance policy and adversarial ERC-20 behavior remain outside
  that model.
- Synchronization proofs use one representative registered asset and the reachable three-Operator aggregate-weight bound
  of 37,500.
- Foundry tests separately cover multi-asset transitions, fee-on-transfer rejection, reentrancy, and the complete pinned
  5,555-Operator canonical lifecycle.
- The variable-denominator quotient/remainder identity has 10,000-run Foundry fuzz evidence and is not claimed as an
  exhaustive symbolic proof.
