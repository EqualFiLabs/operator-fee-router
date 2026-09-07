using FormalOperatorSystem as system;
using FormalRewardTokenA as tokenA;
using FormalRewardTokenB as tokenB;

ghost mapping(address => mathint) addedGhost {
    init_state axiom forall address asset. addedGhost[asset] == 0;
}

ghost mapping(address => mathint) claimedGhost {
    init_state axiom forall address asset. claimedGhost[asset] == 0;
}

ghost mapping(address => mathint) liabilityGhost {
    init_state axiom forall address asset. liabilityGhost[asset] == 0;
}

hook Sstore rewardBook[KEY address asset].totalAdded uint256 newValue (uint256 oldValue) {
    addedGhost[asset] = addedGhost[asset] + to_mathint(newValue) - to_mathint(oldValue);
}

hook Sstore rewardBook[KEY address asset].totalClaimed uint256 newValue (uint256 oldValue) {
    claimedGhost[asset] = claimedGhost[asset] + to_mathint(newValue) - to_mathint(oldValue);
}

hook Sstore rewardBook[KEY address asset].accountedLiability uint256 newValue (uint256 oldValue) {
    liabilityGhost[asset] = liabilityGhost[asset] + to_mathint(newValue) - to_mathint(oldValue);
}

methods {
    function rewardA() external returns (address) envfree;
    function rewardB() external returns (address) envfree;
    function routerTimelock() external returns (address) envfree;
    function operatorVault() external returns (address) envfree;
    function bootstrapFinalized() external returns (bool) envfree;
    function totalEffectiveWeight() external returns (uint256) envfree;
    function rewardAssetCount() external returns (uint256) envfree;
    function isRewardAsset(address) external returns (bool) envfree;
    function rewardAssetEnabled(address) external returns (bool) envfree;
    function syncedOwner(uint256) external returns (address) envfree;
    function syncedMultiplierBps(uint256) external returns (uint16) envfree;
    function formalOperatorInitialized(uint256) external returns (bool) envfree;
    function formalBookIndex(address) external returns (uint256) envfree;
    function formalBookIndexRemainder(address) external returns (uint256) envfree;
    function formalBookTotalAdded(address) external returns (uint256) envfree;
    function formalBookTotalClaimed(address) external returns (uint256) envfree;
    function formalBookLiability(address) external returns (uint256) envfree;
    function formalBookTotalForfeited(address) external returns (uint256) envfree;
    function formalBookForfeitedRemainder(address) external returns (uint256) envfree;
    function pendingOperatorRewards(uint256, address) external returns (uint256) envfree;

    // The harness constructor is already finalized. Removing these unreachable lifecycle entry
    // points prevents their guaranteed reverts from being misreported as vacuous invariant cases.
    function bootstrapOperators(uint256) external returns (uint256, uint256) => NONDET DELETE;
    function finalizeBootstrap() external => NONDET DELETE;

    function system.ownerOf(uint256) external returns (address) envfree;
    function system.multiplierBps(uint256) external returns (uint16) envfree;
    function tokenA.balanceOf(address) external returns (uint256) envfree;
    function tokenB.balanceOf(address) external returns (uint256) envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

    // SafeERC20's assembly call is rerouted to the linked exact-token implementation so the
    // proof models token storage precisely instead of accepting an unresolved-call havoc.
    function _.safeTransfer(address token, address to, uint256 value) internal with(env e)
        => cvlSafeTransfer(executingContract, e, token, to, value) expect void;
    function _.safeTransferFrom(address token, address from, address to, uint256 value) internal with(env e)
        => cvlSafeTransferFrom(e, token, from, to, value) expect void;
}

function cvlSafeTransfer(address executing, env e, address token, address to, uint256 value) {
    bool success = token.transferFrom(e, executing, to, value);
    require success;
}

function cvlSafeTransferFrom(
    env e,
    address token,
    address from,
    address to,
    uint256 value
) {
    bool success = token.transferFrom(e, from, to, value);
    require success;
}

/// Ghost ledgers independently track all three authoritative book counters.
invariant ghostLedgersMatchStorage(address asset)
    addedGhost[asset] == to_mathint(formalBookTotalAdded(asset))
        && claimedGhost[asset] == to_mathint(formalBookTotalClaimed(asset))
        && liabilityGhost[asset] == to_mathint(formalBookLiability(asset))
    {
        preserved with (env e) {
            require bootstrapFinalized();
            require rewardAssetCount() <= 2;
        }
    }

/// Accounted liability is exactly cumulative additions less cumulative claims.
invariant liabilityEqualsAddedMinusClaimed(address asset)
    to_mathint(formalBookLiability(asset))
        == to_mathint(formalBookTotalAdded(asset)) - to_mathint(formalBookTotalClaimed(asset))
    {
        preserved with (env e) {
            require bootstrapFinalized();
            require rewardAssetCount() <= 2;
        }
    }

/// Each linked exact-transfer reward token always covers its recorded liability.
invariant rewardATokenSolvency()
    to_mathint(tokenA.balanceOf(currentContract)) >= to_mathint(formalBookLiability(rewardA()))
    {
        preserved with (env e) {
            require bootstrapFinalized();
            require rewardAssetCount() <= 2;
        }
    }

invariant rewardBTokenSolvency()
    to_mathint(tokenB.balanceOf(currentContract)) >= to_mathint(formalBookLiability(rewardB()))
    {
        preserved with (env e) {
            require bootstrapFinalized();
            require rewardAssetCount() <= 2;
        }
    }

/// A successful permissionless contribution changes custody, addition, and liability by exactly `amount`.
rule addRewardsHasExactDeltas(env e, uint256 amount) {
    address asset = rewardA();
    require e.msg.value == 0;
    require e.msg.sender != currentContract;
    require bootstrapFinalized();
    require rewardAssetCount() <= 2;
    require isRewardAsset(asset);
    require rewardAssetEnabled(asset);
    require totalEffectiveWeight() > 0;
    require amount > 0;
    require to_mathint(formalBookLiability(asset)) + amount <= 79228162514264337593543950335;
    require tokenA.balanceOf(e.msg.sender) >= amount;
    require to_mathint(tokenA.balanceOf(currentContract)) + amount <= max_uint256;

    uint256 addedBefore = formalBookTotalAdded(asset);
    uint256 claimedBefore = formalBookTotalClaimed(asset);
    uint256 liabilityBefore = formalBookLiability(asset);
    uint256 routerBalanceBefore = tokenA.balanceOf(currentContract);
    uint256 senderBalanceBefore = tokenA.balanceOf(e.msg.sender);

    addRewards(e, asset, amount);

    assert to_mathint(formalBookTotalAdded(asset)) == to_mathint(addedBefore) + amount,
        "addition counter must increase exactly";
    assert formalBookTotalClaimed(asset) == claimedBefore,
        "contribution must not change claims";
    assert to_mathint(formalBookLiability(asset)) == to_mathint(liabilityBefore) + amount,
        "liability must increase exactly";
    assert to_mathint(tokenA.balanceOf(currentContract)) == to_mathint(routerBalanceBefore) + amount,
        "router custody must increase exactly";
    assert to_mathint(tokenA.balanceOf(e.msg.sender)) == to_mathint(senderBalanceBefore) - amount,
        "contributor balance must decrease exactly";
}

/// A no-transition claim pays exactly the reported pending amount and reduces custody and liability together.
rule claimHasExactDeltas(env e, address receiver) {
    address asset = rewardA();
    require e.msg.value == 0;
    require rewardAssetCount() <= 2;
    require isRewardAsset(asset);
    require formalOperatorInitialized(1);
    require system.ownerOf(1) == syncedOwner(1);
    require system.multiplierBps(1) == syncedMultiplierBps(1);
    require e.msg.sender == syncedOwner(1);
    require e.msg.sender != operatorVault();
    require receiver != 0 && receiver != currentContract;

    uint256 pending = pendingOperatorRewards(1, asset);
    require pending > 0;
    require formalBookLiability(asset) >= pending;
    require tokenA.balanceOf(currentContract) >= pending;
    require to_mathint(tokenA.balanceOf(receiver)) + pending <= max_uint256;

    uint256 addedBefore = formalBookTotalAdded(asset);
    uint256 claimedBefore = formalBookTotalClaimed(asset);
    uint256 liabilityBefore = formalBookLiability(asset);
    uint256 routerBalanceBefore = tokenA.balanceOf(currentContract);
    uint256 receiverBalanceBefore = tokenA.balanceOf(receiver);

    uint256 claimed = claimOperatorRewards(e, 1, asset, receiver);

    assert claimed == pending, "claim must equal the pre-call pending amount";
    assert formalBookTotalAdded(asset) == addedBefore,
        "claim must not change cumulative additions";
    assert to_mathint(formalBookTotalClaimed(asset)) == to_mathint(claimedBefore) + claimed,
        "claim counter must increase exactly";
    assert to_mathint(formalBookLiability(asset)) == to_mathint(liabilityBefore) - claimed,
        "claim must reduce liability exactly";
    assert to_mathint(tokenA.balanceOf(currentContract)) == to_mathint(routerBalanceBefore) - claimed,
        "claim must reduce router custody exactly";
    assert to_mathint(tokenA.balanceOf(receiver)) == to_mathint(receiverBalanceBefore) + claimed,
        "receiver must be paid exactly";
}

/// Timelocked surplus recovery cannot mutate any reward-accounting field.
rule recoverSurplusPreservesAccounting(env e, address receiver, uint256 amount) {
    address asset = rewardA();
    require e.msg.value == 0;
    require e.msg.sender == routerTimelock();
    require receiver != 0 && receiver != currentContract;
    require amount > 0;
    require tokenA.balanceOf(currentContract) >= formalBookLiability(asset);
    require to_mathint(tokenA.balanceOf(currentContract))
        >= to_mathint(formalBookLiability(asset)) + amount;
    require to_mathint(tokenA.balanceOf(receiver)) + amount <= max_uint256;

    uint256 indexBefore = formalBookIndex(asset);
    uint256 indexRemainderBefore = formalBookIndexRemainder(asset);
    uint256 addedBefore = formalBookTotalAdded(asset);
    uint256 claimedBefore = formalBookTotalClaimed(asset);
    uint256 liabilityBefore = formalBookLiability(asset);
    uint256 forfeitedBefore = formalBookTotalForfeited(asset);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(asset);
    uint256 routerBalanceBefore = tokenA.balanceOf(currentContract);

    recoverSurplus(e, asset, receiver, amount);

    assert formalBookIndex(asset) == indexBefore;
    assert formalBookIndexRemainder(asset) == indexRemainderBefore;
    assert formalBookTotalAdded(asset) == addedBefore;
    assert formalBookTotalClaimed(asset) == claimedBefore;
    assert formalBookLiability(asset) == liabilityBefore;
    assert formalBookTotalForfeited(asset) == forfeitedBefore;
    assert formalBookForfeitedRemainder(asset) == forfeitedRemainderBefore;
    assert to_mathint(tokenA.balanceOf(currentContract)) == to_mathint(routerBalanceBefore) - amount,
        "only surplus custody may leave";
}

/// A contribution to reward A cannot mutate reward B's independent book or custody.
rule rewardAssetsAreIsolated(env e, uint256 amount) {
    address assetA = rewardA();
    address assetB = rewardB();
    require e.msg.value == 0;
    require e.msg.sender != currentContract;
    require assetA != assetB;
    require bootstrapFinalized();
    require rewardAssetCount() == 2;
    require isRewardAsset(assetA) && isRewardAsset(assetB);
    require rewardAssetEnabled(assetA);
    require totalEffectiveWeight() > 0;
    require amount > 0;
    require to_mathint(formalBookLiability(assetA)) + amount <= 79228162514264337593543950335;
    require tokenA.balanceOf(e.msg.sender) >= amount;
    require to_mathint(tokenA.balanceOf(currentContract)) + amount <= max_uint256;

    uint256 indexBefore = formalBookIndex(assetB);
    uint256 indexRemainderBefore = formalBookIndexRemainder(assetB);
    uint256 addedBefore = formalBookTotalAdded(assetB);
    uint256 claimedBefore = formalBookTotalClaimed(assetB);
    uint256 liabilityBefore = formalBookLiability(assetB);
    uint256 forfeitedBefore = formalBookTotalForfeited(assetB);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(assetB);
    uint256 balanceBefore = tokenB.balanceOf(currentContract);

    addRewards(e, assetA, amount);

    assert formalBookIndex(assetB) == indexBefore;
    assert formalBookIndexRemainder(assetB) == indexRemainderBefore;
    assert formalBookTotalAdded(assetB) == addedBefore;
    assert formalBookTotalClaimed(assetB) == claimedBefore;
    assert formalBookLiability(assetB) == liabilityBefore;
    assert formalBookTotalForfeited(assetB) == forfeitedBefore;
    assert formalBookForfeitedRemainder(assetB) == forfeitedRemainderBefore;
    assert tokenB.balanceOf(currentContract) == balanceBefore;
}
