# Operator Fee Router architecture

## Trust boundary

`OperatorFeeRouter` is an immutable accounting and ERC-20 custody contract. It has no Statics Diamond address, no
Operator callback, and no ability to modify Operator ownership or activation. Its only canonical reads are:

- `ownerOf(operatorId)` from the Statics Operator NFT;
- `multiplierBps(operatorId)` from the activation registry; and
- the Operator vault address, which always maps to zero reward weight.

The immutable router timelock may register or disable reward assets and recover only token balances exceeding recorded
liability. Its initial and minimum future delay is 24 hours. Execution is open, while the deployment proposer must be a
verified multisig or Governor. Ready OpenZeppelin timelock operations do not expire automatically, so the proposer must
cancel superseded operations. The timelock cannot edit indexes, synchronized Operator state, checkpoints, or claims. V1
has no proxy, guardian, or global pause.

## Accounting

Each registered ERC-20 has a RAY-scaled global index and full-precision numerator remainder. Each Operator has a
synchronized owner, multiplier, effective weight, per-asset index checkpoint, accrued whole tokens, and a sub-token
settlement remainder.

`addRewards(asset, amount)` is permissionless after bootstrap and pulls an exact amount. It rejects fee-on-transfer
behavior, indexes against the current synchronized total weight, and never iterates over Operators. Direct transfers do
not affect indexes and are recoverable only to the extent that they exceed recorded liability. Rebasing and otherwise
non-exact assets are outside V1's supported asset set.

Each asset's outstanding liability is capped at `type(uint96).max` base units. At the minimum 10,000 weight denominator,
this preserves more than `1e25` maximum-sized index increments before the `uint256` index boundary, eliminating practical
index-saturation griefing while remaining well above conventional 18-decimal reward supplies. Governance onboarding must
also reject assets whose fees, rebases, pause, blocklist, or implementation can later change exact transfer behavior;
disabling deposits cannot repair a token that stops honoring existing claims.

As defense in depth, a forfeiture that cannot fit in an asset's remaining index headroom is queued under the excluded
Operator instead of reverting the whole synchronization. New deposits and explicit pending flushes revert at that
boundary, but synchronization and claims for every other asset remain live.

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
