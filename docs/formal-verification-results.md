# Formal verification summary

The October 24–25, 2026 campaign completes the stated bounded verification through a
composition of native proofs and successful-call witnesses. Production Solidity was unchanged.
The versioned source and verification inputs match commit
`78144c2d9b86d9b9e5a06c8ae74af44a591a6f10` byte for byte. Detailed proof inputs, native
reports, models, commands, compiler bindings and execution records remain private.

## Coverage

| Coverage | Result |
| --- | --- |
| Halmos: timelock roles and delay | 5 checks pass |
| Halmos: synchronization and installed weight | 4 checks pass |
| Halmos: lifecycle, authority, retirement and bounded bootstrap | 23 checks pass |
| Certora: index and settlement arithmetic | 7 definitions pass |
| Certora: accounting and exact-token solvency | 8 definitions pass |
| Certora: structural conservation | 3 definitions pass |
| Certora: activation, transfers, forfeiture and claims | 10 definitions pass |
| Coupled normalization and economic conservation | Both constructor bases and all 18 method-preservation obligations complete by composition |
| Synchronization partition | Exact classifier; preservation for six transition types, three Operator positions and both assets; 36 native execution witnesses |
| Claim preservation | No-op, activation and transfer for all three Operator positions; 9 preservation partitions completed by composition and 9 successful execution witnesses |

The 70 original Certora definitions map to 29 native verified definitions, 39 synchronization
definitions discharged by stronger all-path proofs, and the two completed coupled invariants.
This is a composition result rather than 70 native whole-job passes.

The 32 Halmos checks and the 28 Certora prerequisite definitions were retained after checking
input identity and their completed native evidence. The closure uses the source-built prover;
no hosted jobs were submitted for this execution.

## How the proofs compose

Normalization and economic conservation are proved together. Each has a verified constructor
base and preservation for registration, deposit enablement, reward ingress, synchronization,
claims, pending-forfeiture flushing, reward preview, surplus recovery and deregistration.
Their predicates are used as prestate hypotheses. Structural invariants and production
arithmetic are established independently.

Three all-path synchronization theorems cover the original 36 transition-preservation cases
and the three by-Operator definitions. The classifier proves the six cases disjoint and
exhaustive: no-op, activation, multiplier decrease, vault entry, vault exit and ownership
change. Owners, multipliers, amounts, remainders, registry membership and registry order
remain symbolic within the scene bounds.

Claims are partitioned by the three production synchronization branches and Operator position.
The tracked asset and claimed asset remain symbolic. Checks cover payout, liability changes,
settlement, other-Operator state, normalization and the complete economic equation. Separate
proofs establish that assets outside the linked scene retain normalized accounting.

The economic equation is:

```text
liability * RAY + sum(weight * checkpoint)
  == indexRemainder + totalWeight * index + sum(recordedEntitlement)
```

With the independently proved aggregate-weight invariant, this is equivalent to liability scaled by RAY
equaling all complete scaled entitlements plus the index remainder. Entitlements include
accrued amounts, unsettled index entitlement, settlement remainders and queued forfeitures.
Retired assets retain historical records while live liability expires.

Only the two pure arithmetic helpers are replaced by quotient/remainder relations in the
universal accounting proofs. Every caller-domain condition remains an assertion. Four
unconditional algebraic lemmas establish product identities before their instantiation in
router proofs. Asset-isolation proofs instead overapproximate the pure helpers by arbitrary
returns without storage writes, proving isolation independently of arithmetic outputs.

Completed safety subrules and explicit native SAT witnesses are composed without changing
any original job status. Earlier monolithic and automatic-sanity attempts remain incomplete.
Two transfer runs completed every production-state assertion but timed out on a pre-call algebra identity. A
separate generic proof establishes that exact identity under weaker preconditions, using
an independently proved product lemma. Their completed checks are reused in the composition.
The 36 synchronization witness goals all produced verified models; their separate aggregate
assertion group timed out. Those goals provide existence evidence only. Universal safety is
supplied by the completed preservation proofs. No timeout, unknown, vacuous rule or unrun
obligation is labeled a native pass.

## Bounds and assumptions

The router scene contains three initialized Operators and two distinct linked exact-transfer
tokens. Operator-addressed calls are restricted to those three positions, and registration is
restricted to the linked tokens. Canonical dependencies are modeled. Loops are checked
pessimistically with bound 4; unwinding conditions are asserted.

Operational invariants begin after bootstrap. Separate Halmos properties execute bounded
production bootstrap batches and finalization, including arbitrary valid cursors and an
abstract prior aggregate. This is not symbolic execution over all 5,555 Operators. Registry
removal checks use two and three assets, rather than all 64 slots.

Production index arithmetic covers amounts through `uint96.max`, fractional input below
`1e27`, prior index remainder below 69,437,500 and denominators 10,000–69,437,500.
Settlement covers weights 0–12,500, normalized prior remainder and scaled entitlement through
`uint96.max * 1e27`. Router composition uses the narrower three-Operator total of at most
37,500. Valid-call properties state arithmetic headroom; unlimited lifetime capacity is not
proved.

Token behavior follows the linked exact-transfer models. Allowance policies, callbacks,
rebasing and arbitrary selector-specific token behavior are outside that model. The results
establish the stated bounded properties; fork checks and live deployment validation are
separate evidence.

## Reproduction and complementary evidence

The versioned proof suites and runners remain available. The hosted runner requires a
credential and submits remote jobs; this closure instead used the source-built prover with
private, decomposed proof inputs. Running only the unchanged monolithic economic suite may
still time out. The completion record binds each retained or composed obligation to its
actual compiled inputs and native result.

Existing CI runs the timelock and synchronization Halmos suites. The complete remote Halmos
runner additionally covers lifecycle properties. Earlier mutation checks and 78 passing
non-fork Foundry tests remain complementary historical evidence; this closure did not rerun
those tests or add fork, live-chain or deployment evidence.

## Toolchain and bindings

| Component | Verified configuration |
| --- | --- |
| Solidity | 0.8.33+commit.64118f21; Cancun; optimizer 200; via IR disabled |
| Foundry | 1.7.1 |
| Halmos | 0.3.3 |
| Certora prover source | `f5f77783430449791186f7812ebd53addf22cabd` |
| Runtime and solvers | Java 21.0.12.1; Z3 4.16.0; CVC5 1.4.2 |
| forge-std | `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b` |
| OpenZeppelin | `5fd1781b1454fd1ef8e722282f86f9293cacf256` |

The prover JAR SHA-256 is
`a868bbe87a01002e5955cfd2084ac8817818cd64380ae96227a604d4d22044ec`.
The production source SHA-256 is
`a196ec19bb42e5f1a089bd0331bbb97c2e3d1844cc84b1449ef3249c5367c284`.

The metadata-free production runtime template is 12,423 bytes, SHA-256
`995e87587fd65cd0e74ee0171b6cdd57e67616494c92fbd37da162a846af4912`.
It contains unresolved immutables and is not a deployed runtime hash. Each proof retains its
own compiler output and instrumented-bytecode hashes in the private evidence archive.
