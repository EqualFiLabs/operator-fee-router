# Operator router mainnet fork rehearsal

This campaign deploys the production router and dedicated timelock onto a pinned Robinhood Mainnet fork, then executes lifecycle and adversarial transactions with `cast`. It never broadcasts to the upstream chain. No production contract is modified.

Load the private RPC configuration into the shell first. The runner requires `ROBINHOOD_MAINNET`, Python 3, Forge, cast, Anvil and the repository submodules. Keep RPC values out of command history and logs.

```bash
scripts/mainnet-rehearsal/run-all.sh
```

The default uses a fresh executable upstream block, verifies chain ID 4663 and the canonical contract bindings, and records its height and hash. Use `--block <height>` to reproduce a previous anchor if the provider still serves that state. `--seed <integer>` and `--steps <count>` control the composed campaign; at least 160 steps are required for a complete run. Shorter runs are labelled diagnostic. An occupied port is an error; use `--port <unused-port>` without disturbing other services.

All writes require numeric loopback HTTP, Anvil client identity, chain ID, the original block hash and a run ownership marker. A detached supervisor preserves the fork after a client disconnect and redacts upstream URLs from service output. Native balances are seeded for wallet gas; the canonical vault is never used as a top-level signer or gas-seeded. Minting is restricted to locally deployed synthetic assets. Run evidence lives in the ignored `.rehearsal-results/` directory with owner-only permissions. It includes the source revision and content hashes, compiler settings, tool versions, deployment/runtime hashes, transaction inputs, receipts, call traces, read observations, invariant checks and selector coverage. Do not commit generated evidence or internal review notes.

The process prints its private run directory. After completion:

```bash
python3 scripts/mainnet-rehearsal/verify.py <run-directory>
python3 scripts/mainnet-rehearsal/rehearse.py stop <run-directory>
```

Stopping checks process ownership and affects only that run. A failed campaign remains failed and retains its evidence and fork for investigation. Re-running creates a new campaign; it does not silently resume or reuse a previous campaign's success.

## Exercised behavior

- Production constructor bindings and bytecode comparison, bootstrap boundaries and all 5,555 canonical Operators.
- Real WETH and STATICS funding, exact deposits, owner-only claims, alternate receivers, duplicate claims and invalid inputs.
- Real STATICS-funded activation, prospective weights, NFT approvals and transfers, activation reset, lazy synchronization and forfeiture.
- Real vault redemption and reacquisition, backing and reserve accounting, zero vault weight and restored circulating weight. Canonical ERC-20 balances, code and storage are never replaced; activation funding comes from an existing holder.
- Zero-decimal and 18-decimal assets, rejection above 18 decimals, fractional rewards, the exact outstanding-liability cap and replenishment after claims.
- Synthetic receiver-fee, sender-fee, false-return, blocked-transfer and callback assets. Both ingress and outgoing claims are exercised. These fixtures describe hostile behavior; they make no claim about the live tokens.
- Direct claim-only controls; claims during the notice window; timelocked expiry and recovery; premature/cancelled execution; minimum delay; proposer/canceller coupling; batch rollback and liability protection.
- All 64 asset slots populated, cold transfer and claim-triggered synchronization with an explicit 15-million-gas campaign budget.
- A seeded composed sequence of deposits, claims, transfers, no-op synchronization, claim-only toggles, unauthorized recovery attempts, time changes and donations. State accumulates across the sequence.
- A separately labelled synthetic collection exercises zero total weight and sole-holder fractional queued forfeiture/flush. The mainnet collection remains intact.

After state transitions, the observer sums installed weights and scaled reward entitlements across all 5,555 IDs. Checks require:

```
sum(installed weights) = totalEffectiveWeight
totalAdded = totalClaimed + accountedLiability + expiredRewards
router token balance >= accountedLiability
availableSurplus = router token balance - accountedLiability
accountedLiability * RAY = sum(all unclaimed scaled entitlements) + indexRemainder
```

The last equality applies to registered assets. Entitlements include accrued amounts, unsettled index rewards, settlement fractions and queued forfeiture fractions. Canonical comparisons run at bootstrap and reconciled lifecycle boundaries; they are not imposed during intentionally stale ownership intervals.

Expected failures must be mined with status zero and the expected error selector in the root trace. Financial snapshots must remain unchanged where asserted. Successful receipts, committed nested governance execution and views are recorded separately. Reverted batches do not earn successful coverage. Queue/flush success is credited only to its synthetic scene.

## Boundaries

This is finite fork evidence, not an exhaustive proof or a mainnet deployment. Impersonation exercises authorization and contract execution but does not validate Safe signatures, signing hardware, real deployment key custody, RPC broadcast policy or production transaction ordering. The runner uses compiled creation bytecode through cast; it does not certify the production deployment script or final manifest publisher. The gas budget is a local campaign threshold, not a claim about future chain limits. Concurrent upstream activity is frozen at the anchor. Transfer round trips that restore identical ownership and activation before synchronization retain the documented lazy-observation limitation.

Run the existing Foundry fuzz/invariant suites and the separately documented formal verification in their authorized environments as complementary validation. This runner invokes neither Halmos nor Certora.
