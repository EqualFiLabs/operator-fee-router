# Robinhood Mainnet

Chain ID: **4663**. The [deployment record](operator-fee-router.json) contains contract addresses,
source and toolchain identities, runtime code hashes, creation receipts, bootstrap transactions,
and reward-asset registration provenance.

| Contract | Address |
|---|---|
| Operator Fee Router | [`0x938A4B0F6240f8909544967cF51c70e3EB7c3A59`](https://robinhoodchain.blockscout.com/address/0x938A4B0F6240f8909544967cF51c70e3EB7c3A59) |
| Router Timelock | [`0x94829084Fca41ECE4648D328caEfc813a4Bc8A5b`](https://robinhoodchain.blockscout.com/address/0x94829084Fca41ECE4648D328caEfc813a4Bc8A5b) |
| Governance Safe | [`0x603A8A2f22ac1d61E9c932A4F6Fa23170CEcb9Ff`](https://robinhoodchain.blockscout.com/address/0x603A8A2f22ac1d61E9c932A4F6Fa23170CEcb9Ff) |

The Safe uses a 2-of-2 threshold and holds the timelock proposer and canceller roles. The timelock
delay is **86,400 seconds**, execution is open, and role administration belongs to the timelock itself.
Asset registration and deposit enablement are available directly to the Safe through its proposer role.

Bootstrap initialized all **5,555 Operators** in 56 batches, followed by finalization. The completed
cursor is **5,556**. At block **112,844,176**, all installed owner and multiplier snapshots matched
canonical state, and their weights summed to **11,461,000**.

| Reward asset | Address | Decimals | Deposits |
|---|---|---:|---|
| USDG | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | 6 | Enabled |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | 18 | Enabled |

Both assets were registered by the Safe in
[one transaction](https://robinhoodchain.blockscout.com/tx/0x3c7f6517a01bb9944ea3f2079278b11d028c609304b2fe42ec8eff25014dc086)
at block **112,860,064**. Their registered and enabled state, the finalized bootstrap, and both deployed
runtime code hashes were checked at block **112,864,197**. The recorded configuration is a snapshot;
read current state before integrating or submitting transactions.
