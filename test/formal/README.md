# Formal verification

This directory contains bounded Halmos and Certora harnesses for the production Router and timelock.

## Halmos

The timelock harness proves, for every `uint256` proposed delay, that values below 24 hours fail without changing the
delay and values at or above 24 hours succeed. The Operator sync harness executes the production Router against bounded
canonical mocks and proves these transition classes over every supported multiplier in each stated range:

- an equal owner/multiplier snapshot is a no-op;
- a same-owner increase is an activation and replaces exactly the old weight;
- a same-owner decrease uses forfeiting transfer semantics; and
- an owner mismatch uses transfer semantics at every valid multiplier.

All Solidity panic codes are proof failures:

```bash
halmos --contract OperatorFeeRouterTimelockHalmosTest --solver-timeout-assertion 2m --panic-error-codes '*'
halmos --contract OperatorSyncHalmosTest --solver-timeout-assertion 2m --panic-error-codes '*'
```

## Certora

The Certora harness inherits the production `OperatorFeeRouter`; it does not reproduce its accounting or synchronization
logic. The model uses three Operators and two linked exact-transfer reward tokens. Only bootstrap sizing and the
canonical/token dependencies are substituted. The operational accounting invariants assume a finalized bootstrap.
SafeERC20's assembly call is rerouted to the linked exact-token implementation; allowance policy is outside this model.
Both configurations use Solidity 0.8.33, Cancun, optimizer 200, sufficient loop unwinding for the bounded scene,
`optimistic_loop=false`, and basic rule-sanity checks.

Set `CERTORAKEY` in the environment without printing it, then run:

```bash
scripts/run-certora.sh accounting
scripts/run-certora.sh sync
scripts/run-certora.sh all
```

## Results and complementary evidence

Completed proof results and precise model bounds are recorded in
[formal-verification-results.md](../../docs/formal-verification-results.md). Foundry separately provides 10,000-run fuzz
checks under the security profile, an eight-Operator/three-asset stateful invariant suite, and the pinned full
5,555-Operator Robinhood lifecycle fork.
