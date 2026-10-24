# Formal verification summary

This is the central guide to formal coverage, execution, model bounds, and recorded outcomes.
Proof specifications, harnesses, and runners are versioned. Generated reports, logs, result JSON,
acceptance records, and mutation artifacts stay outside version control.

The October 23–24, 2026 campaign used production source unchanged from main commit
`5b64a73d8c9a9b93609e50fe5950546e91108674`. The complete economic-conservation bundle
remains incomplete; these results do not establish mainnet deployment readiness.

## Running the proofs

Run Halmos and Certora in a verification environment with the documented toolchain.
Verify the exact checkout, dependencies, compiler settings, and tool versions before
execution. Keep logs and input manifests in durable storage outside version control.

```bash
scripts/run-halmos.sh
scripts/run-certora.sh math
scripts/run-certora.sh settlement
scripts/run-certora.sh accounting
scripts/run-certora.sh conservation
scripts/run-certora.sh sync
scripts/run-certora.sh economic
# Submit the six main Certora suites, including prerequisites:
scripts/run-certora.sh all
```

The Certora runner above submits hosted jobs and requires `CERTORAKEY`. Read any
credential file as data; never source or print it. For self-hosted execution, invoke
your source-built prover launcher directly with a configuration; no hosted credential
is required. `all` does not run the supplemental by-ID or transition-case configurations.
Individual suite passes remain conditional on their prerequisites below.

The Halmos runner uses loop bound 4, a two-minute assertion timeout, and all Solidity panic
codes as failures. It requires exactly 5, 4, and 23 passing checks and rejects warnings,
errors, failed assertions, and incomplete output. Logs go to `.formal-results/` or
`FORMAL_LOG_DIR`. A timeout, unknown result, vacuous rule, unexplored loop, or terminated
process is never a passing proof.

CI currently runs only the timelock and synchronization Halmos harnesses. Lifecycle coverage
is included in the complete Halmos runner. Formal runs, ordinary Foundry tests, CI, fork
checks, and live-chain validation are separate evidence.

## Coverage and recorded outcomes

Execution snapshot IDs below refer to the original pre-squash commits retained with remote
proof inputs. They identify the inputs actually executed, rather than asserting that every
later specification revision was rerun. Relevant input comparisons are retained with the
remote evidence; documentation and history cleanup do not change proof semantics.

### Halmos — October 23

Verified snapshot: `3ce20c6a8c7c45f799b4d292e35b7d2612da9ed6`; runner exit 0.
All logs were checked for warnings, errors, unexplored loops, and exact pass counts.
Earlier bootstrap attempts with loop warnings are excluded.

| Harness | Coverage | Properties | Outcome |
| --- | --- | ---: | --- |
| `OperatorFeeRouterTimelockHalmosTest` | Minimum delay; proposer/canceller coupling at construction, grant, revoke, and renunciation | 5 | Pass |
| `OperatorSyncHalmosTest` | No-op, prospective activation, multiplier decrease, ownership transfer, exact installed-weight deltas | 4 | Pass |
| `RouterLifecycleHalmosTest` | Authority boundaries; scheduled expiry; claim-only and retirement; registry removal; metadata; invalid IDs; bounded bootstrap | 23 | Pass |
| **Total** | | **32** | **117 paths; pass** |

### Certora — October 23

| Suite | Coverage | Properties | Outcome | Execution snapshot |
| --- | --- | ---: | --- | --- |
| Index arithmetic | Non-reversion, quotient/remainder reconstruction, normalized remainder, zero-denominator rejection | 4 | Pass | `04bbb868b2b9f460ae846e7bd6f4e3bb66240554` |
| Settlement arithmetic | Production `_settlementDelta`: non-reversion, reconstruction, normalized remainder | 3 | Pass | `2d4bb3e86af1d77e5e92a56f6ad27950c328cbe5` |
| Accounting | Added/claimed/expired liability, exact-token solvency, valid contribution/claim/recovery/expiry, isolation | 8 | Pass | `3ce20c6a8c7c45f799b4d292e35b7d2612da9ed6` |
| Transitions | Two-asset activation; funded decrease/transfer; queue/flush; vault exit; claim-triggered sync; former-owner and duplicate-claim rejection | 10 | Pass | `26a5abf8e7c0875909d9c9a2ac54f6db9bfd735f` |
| Structural conservation | Registry consistency/uniqueness, zero state before registration, installed aggregate weight | 3 | Pass | `5669dbd2fe4b477b8da684d033de41ab56e42b9f` |
| Economic conservation | Joint induction of normalization and all scaled entitlements, remainders, and queued forfeitures | — | **Incomplete** | Partial runs do not complete the bundle |

### Local economic synchronization — October 24

The supplemental `OperatorFeeRouterEconomicSyncCases.conf` selects a partition classifier
and 36 preservation rules: six transition cases × three literal Operator IDs × two assets.

| Case | Pre-state canonical comparison | Production branch |
| --- | --- | --- |
| Noop | Same owner, equal multiplier | Noop |
| Activation | Same owner, higher multiplier | Activation |
| Decrease | Same owner, lower multiplier | Transfer |
| EnterVault | Different owner, current owner is the vault | Transfer |
| LeaveVault | Different owner, current owner is not the vault, previous owner is the vault | Transfer |
| OwnerChange | Different owner, neither owner is the vault | Transfer |

The classifier proves the predicates disjoint and exhaustive, including an arbitrary case
number. Each preservation rule executes the complete two-asset production sync and retains
both assets' registry, freshness, normalization and economic preconditions, plus all twelve
pre-state algebra/entitlement assertions. Only the selected transition case is restricted.
Owners, multipliers, registry membership/order, lifecycle state, funding and queued amounts
remain symbolic. Vault and zero-weight cases remain included.

Each attempt selected `economicSyncCasePartitionIsExact` and
`economicSyncCaseActivationId1AssetA`, with one concurrent rule, a 60-second solver limit,
a 900-second global limit, and a 1,080-second wall watchdog. No hosted jobs were submitted.

| Execution snapshot | Change | Classifier | Activation preservation |
| --- | --- | --- | --- |
| `8b1fcc265cd9e9fd08a5d28350a08982c4be177e` | Transition/asset partition | Pass | Timeout on final conservation |
| `8cdc02fdbdf83fd8246cd8314b7e4ebb7e5eb2d2` | Checked state/settlement equalities | Pass | Timeout on aggregate/index distribution; final assertion passes only conditionally |
| `232531362e2aaca8fdf0e4f91b5f98045147eea4` | Pure distribution before storage updates, then checked product congruence | Pass | **Pass, including every preceding assertion and non-vacuity** |

The successful run exited 0 after 360.08 seconds, with 77 verified assertion/generated
subtasks and reachable witnesses for both non-vacuity checks. No unresolved obligation,
assertion timeout, or genuine counterexample remained. The two earlier attempts remain
incomplete results. **Only 1 of 36 preservation cases passed; the other 35 are unrun.**
Normalization preservation and every remaining prerequisite of the simultaneous bundle
must also pass before the economic-conservation gap is closed.

Activation assertions check installed and aggregate weights, unchanged book fields,
checkpoint, exact settlement, other-Operator components, and the aggregate/index product.
The product equality is decomposed into an unbounded `mathint` identity before the call
and a checked equality after the call. These are assertions, not new state assumptions;
no arithmetic domain or original obligation is removed. Retired assets retain the final
identity's existing guard. Production contracts and the Solidity harness were unchanged
by this experiment.

To reproduce the selected self-hosted case with the corresponding proof inputs, set
`CERTORA_LOCAL_BIN` to your source-built prover launcher, then run:

```bash
mkdir -p .formal-results
"$CERTORA_LOCAL_BIN" certora/conf/OperatorFeeRouterEconomicSyncCases.conf \
  --rule economicSyncCasePartitionIsExact economicSyncCaseActivationId1AssetA \
  --smt_timeout 60 --global_timeout 900 --max_concurrent_rules 1 \
  --tool_output .formal-results/local-sync-activation.json
```

### Mutation checks and complementary tests

Four isolated mutations produced the expected counterexamples: omit the prior index
remainder, remove proposer/canceller grant coupling, remove permanent retirement, and omit
the allocation index update while retaining increased liability. The allocation mutation
checks contribution preservation only. None is included in production source, and these
negative controls do not replace a complete positive conservation proof.

The October 23 campaign separately passed 78 non-fork Foundry tests with zero failures
(`forge test --no-match-path '*Fork*'`). No new fork, live-chain readiness check, deployment,
or broadcast formed part of this campaign. The October 24 experiment did not rerun
Foundry or Halmos. Historical September 7 results apply only to their original inputs.

## Model bounds and proof composition

Halmos lifecycle fixtures initialize two Operators and model the finalized bootstrap flag.
Separate bootstrap rules execute production batch/finalization code with arbitrary valid
cursor, one to three processed Operators, symbolic non-vault multiplier, end clamping,
invalid counts/multipliers, and incomplete/duplicate finalization. An abstract prior
aggregate overapproximates initialized prefixes and need not be a sum of individual
weights. This is not symbolic execution of all 5,555 Operators. Registry removal uses two
and three assets, not all 64 slots; fixed amounts and identities are stated in the harness.
A direct timelock caller helper checks the sender boundary; a separate production
schedule/execute property checks early rejection and expiry after the minimum delay.

Certora configurations use Solidity 0.8.33/Cancun/optimizer 200, pessimistic loop unwinding
(`loop_iter=4`, `optimistic_loop=false`), and basic sanity checks. Explicit successful-call
rules use `@withrevert`, immediately check `lastReverted`, and state clear reentrancy and
arithmetic headroom conditions. Sync and economic assertions are checked individually;
every preceding assertion must pass before a later assertion counts.

The Router scene has three initialized Operators and two linked exact-transfer tokens.
The harness/configuration bind the canonical system to `0x1000` and tokens to
`0x2000`/`0x3000`; these are scene identities, not deployment addresses. Runtime canonical
owners/multipliers remain symbolic. Conservation restricts registration to those tokens
and Operator-addressed methods to IDs 1–3. Operational invariants start after bootstrap
and exclude its entry points. Direct CVL storage reads retain the shared production
inheritance harness; storage-analysis or processing failure invalidates a run.

Normalization and economic conservation form one simultaneous-induction bundle. Both
constructor bases and every preservation obligation must pass. Each may require its
companion invariant in the pre-state. Exact-rule/method retries can replace timeouts only
with matching source, harness, specification and semantic configuration; filtered retries
do not supply omitted constructor bases or other methods. Earlier specifications and
partial runs do not independently establish the bundle.

The economic identity is checked per tracked non-retired asset while settlement requires
both linked assets' pre-state identities and executes over both assets. Its factored form is:

```text
liability * RAY + sum(weight * checkpoint)
  == indexRemainder + totalWeight * index + sum(recordedEntitlement)
```

The proved aggregate-weight invariant makes this equivalent to liability equaling all
complete scaled entitlements plus index remainder. Entitlements include accrued tokens,
unsettled index entitlement, settlement remainder, queued amounts and queued remainder.
Retired assets retain historical records, have zero live liability, and never re-register.
Before settling paths, both assets retain six checked algebra/cap assertions each.

Sync and economic specs compose the production arithmetic proofs through
`RouterMathSummaries.spec`, replacing only `_settlementDelta` and `LibIndexMath.indexDelta`
with unique quotient/remainder relations. Caller-domain checks are asserted, not assumed.
Structural conservation is checked independently without arithmetic summaries. A composed
pass requires the direct math and structural prerequisites for matching relevant inputs.

Pure index math covers amounts through `uint96.max`, fractional input below `1e27`, prior
index remainder below 69,437,500, and denominators 10,000–69,437,500, covering the full
collection's denominator range. Settlement summaries allow weights 0–12,500, normalized
prior remainder, and scaled entitlement through `uint96.max * 1e27`. Router summaries use
the narrower three-Operator bounds; transition aggregate weight is at most 37,500.
Nonzero redistribution denominators are at least 10,000. Global index remainder is bounded
by the scene maximum, not by the current denominator after a weight change. Valid-call
rules state lifetime index/counter headroom and bound complete funded entitlement by live
liability; they do not prove unlimited lifetime capacity.

Canonical dependencies and tokens are modeled. SafeERC20 summaries use exact linked-token
balance movement. Allowance policy, callbacks and selector-specific token behavior are
outside that model; Foundry separately covers inexact transfers and reentrancy. These
proofs do not establish arbitrary ERC-20 compatibility.

## Environment and evidence retention

| Component | October 23 hosted/Halmos campaign | October 24 self-hosted experiment |
| --- | --- | --- |
| Foundry | 1.7.1 (`4072e48705af9d93e3c0f6e29e93b5e9a40caed8`) | Existing compiler/dependencies retained |
| Halmos | 0.3.3 | Not executed |
| Certora | CLI/hosted engine 8.18.0, container 1.1.5 | Source commit `f5f77783430449791186f7812ebd53addf22cabd` (release label 8.20.2; CLI reports `local script version`) |
| Solidity | 0.8.33+commit.64118f21, Cancun, optimizer 200 | Same |
| Runtime/solvers | Hosted environment | Java 21.0.12.1, Z3 4.16.0, CVC5 1.4.2 |

Both used forge-std `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b` and OpenZeppelin
`5fd1781b1454fd1ef8e722282f86f9293cacf256`. The self-hosted JAR SHA-256 was
`a868bbe87a01002e5955cfd2084ac8817818cd64380ae96227a604d4d22044ec`.

The metadata-free Foundry Router runtime template was 12,423 bytes, SHA-256
`995e87587fd65cd0e74ee0171b6cdd57e67616494c92fbd37da162a846af4912`.
The shared Certora harness template was 13,887 bytes, SHA-256
`af21872587a9025f82cac2a569a1a07db5de3fee84efb731eb9ffab740f22a5d`.
These were reproduced locally/remotely and contain unresolved immutable placeholders;
they are compiler templates, not deployed runtime hashes or Certora-instrumented hashes.

Input manifests, instrumented-bytecode hashes, logs, reports and diagnostics are retained
outside the repository, grouped by execution snapshot. Generated evidence and scratch
review reports must remain untracked; this summary records outcomes and limits without
publishing those artifacts.
