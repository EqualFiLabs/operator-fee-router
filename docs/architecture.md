# Operator Fee Router architecture

## Trust boundary

`OperatorFeeRouter` is an immutable accounting and ERC-20 custody contract. It has no Statics Diamond address, no
Operator callback, and no ability to modify Operator ownership or activation. Its only canonical reads are:

- `ownerOf(operatorId)` from the Statics Operator NFT;
- `multiplierBps(operatorId)` from the activation registry; and
- the Operator vault address, which always maps to zero reward weight.

The immutable router timelock is the authority for reward expiry and surplus recovery. Its initial and minimum future
delay is 24 hours. Execution is open, while the deployment proposer must be a verified multisig or Governor. Proposers
can register assets and toggle deposits immediately; the timelock itself retains those permissions. Direct management
authority follows the existing `PROPOSER_ROLE`, so role rotation needs no separate Router administrator.
Granting or revoking `PROPOSER_ROLE` also grants or revokes `CANCELLER_ROLE` for that account. Renunciation also removes
both roles. Grant successor authority before removing the sole proposer; otherwise no new operation can be scheduled.

Ready OpenZeppelin timelock operations do not expire automatically. Governance must cancel superseded operations;
re-enabling deposits does not cancel a queued deregistration. The timelock cannot rewrite indexes, synchronized Operator
state, or checkpoints. It can intentionally expire an asset's remaining liabilities through deregistration. V1 has no
proxy, guardian, or global pause.

## Accounting

Each registered ERC-20 has a RAY-scaled global index and full-precision numerator remainder. Each Operator has a
synchronized owner, multiplier, effective weight, per-asset index checkpoint, accrued whole tokens, and a sub-token
settlement remainder.

`addRewards(asset, amount)` is permissionless after bootstrap and pulls an exact amount. It rejects fee-on-transfer
behavior, indexes against the current synchronized total weight, and never iterates over Operators. Direct transfers do
not affect indexes and are recoverable only to the extent that they exceed recorded liability. Rebasing and otherwise
non-exact assets are outside V1's supported asset set.

Registration requires the asset's `decimals()` to return at most 18; missing or invalid metadata reverts registration.
Each asset's outstanding liability is capped at `type(uint96).max` base units (at least 79.2 billion whole tokens).
At the minimum 10,000 weight denominator,
this preserves more than `1e25` maximum-sized index increments before the `uint256` index boundary, eliminating practical
index-saturation griefing while remaining well above conventional 18-decimal reward supplies. Governance onboarding must
also reject assets whose fees, rebases, pause, or blocklist can later change exact transfer behavior;
disabling deposits cannot repair a token that stops honoring existing claims.

Deposits, forfeiture redistribution, and pending-forfeiture flushes use the same checked index update. Arithmetic
overflow reverts the transaction. Forfeitures are queued only when no other effective weight exists.

The collection uses Operator IDs 1 through 5,555. Permissionless bootstrap initializes them in batches of at most 100.
Reward ingress remains unavailable until every ID has been initialized and bootstrap is finalized.

## Synchronization

External state becomes effective only through `syncOperator` or the synchronization performed by a claim:

- An identical owner and multiplier is a no-op.
- A higher multiplier for the same owner settles every asset at the old weight, then applies the higher weight only to
  future index changes.
- A changed owner or lower multiplier settles and forfeits every unpaid whole and fractional entitlement. The old weight
  is removed, the value is redistributed across other synchronized weight, and only then is the current state installed.
- Vault ownership installs zero weight.

The changed Operator ID is checkpointed after redistribution, so neither that ID nor its new holder receives its own
forfeiture. Other NFTs owned by the same address remain ordinary recipients. If no other weight exists, forfeiture is
kept under that Operator ID and asset. `flushPendingForfeiture` can redistribute it only after another weighted Operator
exists, again checkpointing the excluded ID after the index increase.

An external transfer history that restores exactly the synchronized owner and multiplier cannot be detected from these
current-state reads. This is the explicit limitation of the standalone lazy-sync architecture.

Every canonical owner other than the Operator vault receives weight. Sending an Operator to an address that cannot call
the Router can therefore strand its future share, just as it can strand the NFT itself; this is an unsupported owner-key
or custody error, not a Router recovery path.

## Integration

Once the timelock has registered an asset, any revenue source uses the same interface:

```solidity
IERC20(asset).approve(address(router), amount);
router.addRewards(asset, amount);
```

Native revenue must be wrapped before contribution. Claims remain live when an asset is disabled for new deposits.

## Claim-only and permanent deregistration

Disabling deposits leaves the asset registered and included in settlement, activation, transfer forfeiture, and pending
forfeiture redistribution. Claims remain available; governance can re-enable deposits at any time before deregistration.

`deregisterRewardAsset(asset)` requires the timelock caller and a registered asset with disabled deposits. Its execution
is the claim cutoff. It records the complete outstanding liability in `expiredRewards(asset)`, sets liability to zero,
and marks `isRewardAssetDeregistered(asset)` permanently true. The existing book getter retains its ABI. Lifetime
accounting becomes `totalAdded = totalClaimed + accountedLiability + expiredRewards`.

Removal uses a bounded search and swap-and-pop over the maximum 64 registered assets. `rewardAssetCount` and
`rewardAssetAt` enumerate active and claim-only assets; their order is not stable. A removed asset frees a slot for a
new token address. Re-registering the same address is permanently forbidden, including after zero-liability expiry.

The original index, totals, and per-Operator records are retained as history. Those raw records are no longer live
entitlements: deposits, claims, reward previews, pending-forfeiture flushes, and enablement revert for a deregistered
asset. Synchronization skips it. No per-Operator cleanup or token call occurs during deregistration, so a broken token
cannot block the expiry operation. Other assets' books and global Operator weights are unchanged.

Any remaining balance is then surplus under the existing recovery calculation. Deregistration does not transfer it;
recovery remains a separate timelock-authorized action. Existing timelock batching is available without adding a second
lock. A failed recovery in the same batch rolls the entire batch back, including deregistration.

The Router is immutable. This lifecycle applies to fresh deployments; earlier deployment manifests remain historical
evidence for their pinned source and do not describe the updated contract.
