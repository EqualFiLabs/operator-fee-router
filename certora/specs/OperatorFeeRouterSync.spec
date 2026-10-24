import "helpers/RouterMathSummaries.spec";

using FormalOperatorSystem as system;
using FormalRewardTokenA as tokenA;
using FormalRewardTokenB as tokenB;

methods {
    function rewardA() external returns (address) envfree;
    function rewardB() external returns (address) envfree;
    function operatorVault() external returns (address) envfree;
    function rewardAssetCount() external returns (uint256) envfree;
    function rewardAssetAt(uint256) external returns (address) envfree;
    function isRewardAsset(address) external returns (bool) envfree;
    function totalEffectiveWeight() external returns (uint256) envfree;
    function syncedOwner(uint256) external returns (address) envfree;
    function syncedMultiplierBps(uint256) external returns (uint16) envfree;
    function effectiveWeight(uint256) external returns (uint256) envfree;
    function formalOperatorInitialized(uint256) external returns (bool) envfree;
    function formalReentrancyGuardEntered() external returns (bool) envfree;
    function formalBookIndex(address) external returns (uint256) envfree;
    function formalBookIndexRemainder(address) external returns (uint256) envfree;
    function formalBookTotalAdded(address) external returns (uint256) envfree;
    function formalBookTotalClaimed(address) external returns (uint256) envfree;
    function formalBookLiability(address) external returns (uint256) envfree;
    function formalBookTotalForfeited(address) external returns (uint256) envfree;
    function formalBookForfeitedRemainder(address) external returns (uint256) envfree;
    function formalCheckpoint(uint256, address) external returns (uint256) envfree;
    function formalSettlementRemainder(uint256, address) external returns (uint256) envfree;
    function formalAccrued(uint256, address) external returns (uint256) envfree;
    function formalPendingForfeitureAmount(uint256, address) external returns (uint256) envfree;
    function formalPendingForfeitureRemainder(uint256, address) external returns (uint256) envfree;
    function pendingOperatorRewards(uint256, address) external returns (uint256) envfree;

    function system.ownerOf(uint256) external returns (address) envfree;
    function system.multiplierBps(uint256) external returns (uint16) envfree;
    function tokenA.balanceOf(address) external returns (uint256) envfree;
    function tokenB.balanceOf(address) external returns (uint256) envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);

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

// These rules bind one-asset or two-asset scenes explicitly. They do not claim an
// arbitrary-asset proof for all 64 configured reward-asset slots.

/// Raising a multiplier settles a registered asset at the old weight, then installs the new weight prospectively.
rule activationSettlesAtOldWeight(env e) {
    address assetA = rewardA();
    address assetB = rewardB();
    uint256 oldWeight = effectiveWeight(1);
    uint16 oldMultiplier = syncedMultiplierBps(1);
    uint16 newMultiplier = system.multiplierBps(1);
    uint256 totalWeightBefore = totalEffectiveWeight();

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require system.ownerOf(1) == syncedOwner(1);
    require syncedOwner(1) != operatorVault();
    require oldWeight == oldMultiplier;
    require oldMultiplier >= 10000;
    require newMultiplier > oldMultiplier && newMultiplier <= 12500;
    require totalWeightBefore >= oldWeight && totalWeightBefore <= 37500;
    require to_mathint(totalWeightBefore) - oldWeight + newMultiplier <= 37500;
    require rewardAssetCount() == 2;
    require assetA != assetB;
    require rewardAssetAt(0) == assetA && rewardAssetAt(1) == assetB;
    require isRewardAsset(assetA) && isRewardAsset(assetB);

    uint256 indexA = formalBookIndex(assetA);
    uint256 checkpointA = formalCheckpoint(1, assetA);
    uint256 remainderA = formalSettlementRemainder(1, assetA);
    uint256 accruedA = formalAccrued(1, assetA);
    uint256 liabilityA = formalBookLiability(assetA);
    require indexA >= checkpointA;
    require remainderA < 1000000000000000000000000000;
    mathint scaledA = to_mathint(oldWeight) * (indexA - checkpointA) + remainderA;
    // A live Operator's complete scaled entitlement is one term of the conservation
    // identity, so it cannot exceed the asset's uint96-capped live liability.
    require liabilityA <= 79228162514264337593543950335;
    require to_mathint(accruedA) * 1000000000000000000000000000 + scaledA
        <= to_mathint(liabilityA) * 1000000000000000000000000000;

    uint256 indexB = formalBookIndex(assetB);
    uint256 checkpointB = formalCheckpoint(1, assetB);
    uint256 remainderB = formalSettlementRemainder(1, assetB);
    uint256 accruedB = formalAccrued(1, assetB);
    uint256 liabilityB = formalBookLiability(assetB);
    require indexB >= checkpointB;
    require remainderB < 1000000000000000000000000000;
    mathint scaledB = to_mathint(oldWeight) * (indexB - checkpointB) + remainderB;
    require liabilityB <= 79228162514264337593543950335;
    require to_mathint(accruedB) * 1000000000000000000000000000 + scaledB
        <= to_mathint(liabilityB) * 1000000000000000000000000000;

    syncOperator@withrevert(e, 1);
    assert !lastReverted, "valid activation must succeed";

    assert syncedOwner(1) == system.ownerOf(1);
    assert syncedMultiplierBps(1) == newMultiplier;
    assert effectiveWeight(1) == newMultiplier;
    assert to_mathint(totalEffectiveWeight())
        == to_mathint(totalWeightBefore) - oldWeight + newMultiplier,
        "activation must replace exactly one stored weight";
    assert formalCheckpoint(1, assetA) == indexA;
    assert formalSettlementRemainder(1, assetA) < 1000000000000000000000000000;
    assert to_mathint(formalAccrued(1, assetA)) * 1000000000000000000000000000
            + formalSettlementRemainder(1, assetA)
        == to_mathint(accruedA) * 1000000000000000000000000000 + scaledA,
        "asset A must settle at the old weight";
    assert formalCheckpoint(1, assetB) == indexB;
    assert formalSettlementRemainder(1, assetB) < 1000000000000000000000000000;
    assert to_mathint(formalAccrued(1, assetB)) * 1000000000000000000000000000
            + formalSettlementRemainder(1, assetB)
        == to_mathint(accruedB) * 1000000000000000000000000000 + scaledB,
        "asset B must settle at the old weight";
    assert formalBookLiability(assetA) == liabilityA;
    assert formalBookLiability(assetB) == liabilityB;
}

/// A same-owner decrease forfeits the funded entitlement and conserves every scaled unit.
rule lowerMultiplierUsesTransferSemantics(env e) {
    address assetA = rewardA();
    uint256 oldWeight = effectiveWeight(1);
    uint16 oldMultiplier = syncedMultiplierBps(1);
    uint16 currentMultiplier = system.multiplierBps(1);
    uint256 totalWeightBefore = totalEffectiveWeight();
    mathint denominator = to_mathint(totalWeightBefore) - oldWeight;

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require rewardAssetCount() == 1 && rewardAssetAt(0) == assetA && isRewardAsset(assetA);
    require system.ownerOf(1) == syncedOwner(1);
    require syncedOwner(1) != operatorVault();
    require oldWeight == oldMultiplier;
    require oldMultiplier <= 12500;
    require currentMultiplier >= 10000 && currentMultiplier < oldMultiplier;
    require totalWeightBefore > oldWeight && totalWeightBefore <= 37500;
    require denominator >= 10000;

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldIndexRemainder = formalBookIndexRemainder(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    require oldIndexRemainder < 37500;
    require liabilityBefore <= 79228162514264337593543950335;

    mathint scaledForfeiture = to_mathint(oldAccrued) * 1000000000000000000000000000
        + to_mathint(oldWeight) * (oldIndex - oldCheckpoint) + oldSettlementRemainder;
    mathint redistributionNumerator = scaledForfeiture + oldIndexRemainder;
    // This forfeited entitlement is one nonnegative term of live liability conservation.
    require scaledForfeiture > 0;
    require scaledForfeiture
        <= to_mathint(liabilityBefore) * 1000000000000000000000000000;
    require redistributionNumerator <= max_uint256;
    require formalBookForfeitedRemainder(assetA) < 1000000000000000000000000000;
    require redistributionNumerator
        < (to_mathint(max_uint256) - oldIndex + 1) * denominator;
    require to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
            + formalBookForfeitedRemainder(assetA) + scaledForfeiture
        < (to_mathint(max_uint256) + 1) * 1000000000000000000000000000;

    uint256 addedBefore = formalBookTotalAdded(assetA);
    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 forfeitedBefore = formalBookTotalForfeited(assetA);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(assetA);
    uint256 pendingBefore = formalPendingForfeitureAmount(1, assetA);
    uint256 pendingRemainderBefore = formalPendingForfeitureRemainder(1, assetA);

    syncOperator@withrevert(e, 1);
    assert !lastReverted, "valid funded decrease must succeed";

    assert syncedOwner(1) == system.ownerOf(1);
    assert syncedMultiplierBps(1) == currentMultiplier;
    assert effectiveWeight(1) == currentMultiplier;
    assert to_mathint(totalEffectiveWeight())
        == to_mathint(totalWeightBefore) - oldWeight + currentMultiplier;
    assert formalAccrued(1, assetA) == 0;
    assert formalSettlementRemainder(1, assetA) == 0;
    assert formalCheckpoint(1, assetA) == formalBookIndex(assetA);
    assert pendingOperatorRewards(1, assetA) == 0;
    assert formalPendingForfeitureAmount(1, assetA) == pendingBefore;
    assert formalPendingForfeitureRemainder(1, assetA) == pendingRemainderBefore;
    assert formalBookTotalAdded(assetA) == addedBefore;
    assert formalBookTotalClaimed(assetA) == claimedBefore;
    assert formalBookLiability(assetA) == liabilityBefore;
    assert to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
        + formalBookForfeitedRemainder(assetA)
        == to_mathint(forfeitedBefore) * 1000000000000000000000000000
            + forfeitedRemainderBefore + scaledForfeiture;
    assert (to_mathint(formalBookIndex(assetA)) - oldIndex) * denominator
        + formalBookIndexRemainder(assetA) == redistributionNumerator;
}

/// An ownership mismatch forfeits the changed Operator's entire scaled entitlement and redistributes it exactly once.
rule ownerMismatchForfeitureConservesScaledValue(env e) {
    address assetA = rewardA();
    address previousOwner = syncedOwner(1);
    address currentOwner = system.ownerOf(1);
    uint16 currentMultiplier = system.multiplierBps(1);
    uint256 oldWeight = effectiveWeight(1);
    uint256 totalWeightBefore = totalEffectiveWeight();
    mathint denominator = to_mathint(totalWeightBefore) - oldWeight;

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require previousOwner != 0 && previousOwner != operatorVault();
    require currentOwner != 0 && currentOwner != previousOwner;
    require currentMultiplier >= 10000 && currentMultiplier <= 12500;
    require oldWeight == syncedMultiplierBps(1);
    require oldWeight >= 10000 && oldWeight <= 12500;
    require totalWeightBefore > oldWeight && totalWeightBefore <= 37500;
    require denominator >= 10000;
    require rewardAssetCount() == 1;
    require rewardAssetAt(0) == assetA;
    require isRewardAsset(assetA);

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldIndexRemainder = formalBookIndexRemainder(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    require oldIndexRemainder < 37500;
    require liabilityBefore <= 79228162514264337593543950335;

    mathint scaledForfeiture = to_mathint(oldAccrued) * 1000000000000000000000000000
        + to_mathint(oldWeight) * (oldIndex - oldCheckpoint) + oldSettlementRemainder;
    mathint redistributionNumerator = scaledForfeiture + oldIndexRemainder;

    // This forfeited entitlement is one nonnegative term of live liability conservation.
    require scaledForfeiture > 0;
    require scaledForfeiture
        <= to_mathint(liabilityBefore) * 1000000000000000000000000000;
    require redistributionNumerator <= max_uint256;
    require formalBookForfeitedRemainder(assetA) < 1000000000000000000000000000;
    require redistributionNumerator
        < (to_mathint(max_uint256) - oldIndex + 1) * denominator;
    require to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
            + formalBookForfeitedRemainder(assetA) + scaledForfeiture
        < (to_mathint(max_uint256) + 1) * 1000000000000000000000000000;

    uint256 addedBefore = formalBookTotalAdded(assetA);
    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 forfeitedBefore = formalBookTotalForfeited(assetA);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(assetA);
    uint256 pendingBefore = formalPendingForfeitureAmount(1, assetA);
    uint256 pendingRemainderBefore = formalPendingForfeitureRemainder(1, assetA);

    syncOperator@withrevert(e, 1);
    assert !lastReverted, "valid ownership transfer sync must succeed";

    mathint currentWeight = currentOwner == operatorVault() ? 0 : currentMultiplier;
    assert syncedOwner(1) == currentOwner;
    assert syncedMultiplierBps(1) == currentMultiplier;
    assert effectiveWeight(1) == currentWeight;
    assert to_mathint(totalEffectiveWeight())
        == to_mathint(totalWeightBefore) - oldWeight + currentWeight,
        "transfer must replace exactly one stored weight";
    assert formalAccrued(1, assetA) == 0;
    assert formalSettlementRemainder(1, assetA) == 0;
    assert formalCheckpoint(1, assetA) == formalBookIndex(assetA);
    assert pendingOperatorRewards(1, assetA) == 0,
        "the changed Operator must be excluded from its forfeiture redistribution";
    assert formalPendingForfeitureAmount(1, assetA) == pendingBefore;
    assert formalPendingForfeitureRemainder(1, assetA) == pendingRemainderBefore;

    assert formalBookTotalAdded(assetA) == addedBefore;
    assert formalBookTotalClaimed(assetA) == claimedBefore;
    assert formalBookLiability(assetA) == liabilityBefore;
    assert to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
        + formalBookForfeitedRemainder(assetA)
        == to_mathint(forfeitedBefore) * 1000000000000000000000000000
            + forfeitedRemainderBefore + scaledForfeiture,
        "forfeiture bookkeeping must conserve the complete scaled entitlement";
    assert (to_mathint(formalBookIndex(assetA)) - oldIndex) * denominator
        + formalBookIndexRemainder(assetA) == redistributionNumerator,
        "redistribution quotient and remainder must reconstruct the forfeiture numerator";

}

/// A transfer with no other active weight queues the exact scaled forfeiture for a later flush.
rule zeroOtherWeightQueuesForfeiture(env e) {
    address assetA = rewardA();
    address previousOwner = syncedOwner(1);
    address currentOwner = system.ownerOf(1);
    uint16 currentMultiplier = system.multiplierBps(1);
    uint256 oldWeight = effectiveWeight(1);
    uint256 totalWeightBefore = totalEffectiveWeight();

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require previousOwner != 0 && previousOwner != operatorVault();
    require currentOwner != 0 && currentOwner != previousOwner;
    require currentMultiplier >= 10000 && currentMultiplier <= 12500;
    require oldWeight == syncedMultiplierBps(1);
    require oldWeight >= 10000 && oldWeight <= 12500;
    require totalWeightBefore == oldWeight;
    require rewardAssetCount() == 1 && rewardAssetAt(0) == assetA && isRewardAsset(assetA);
    require formalPendingForfeitureAmount(1, assetA) == 0;
    require formalPendingForfeitureRemainder(1, assetA) == 0;

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldIndexRemainder = formalBookIndexRemainder(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    require liabilityBefore <= 79228162514264337593543950335;

    mathint scaledForfeiture = to_mathint(oldAccrued) * 1000000000000000000000000000
        + to_mathint(oldWeight) * (oldIndex - oldCheckpoint) + oldSettlementRemainder;
    // This queued entitlement is one nonnegative term of live liability conservation.
    require scaledForfeiture > 0;
    require scaledForfeiture
        <= to_mathint(liabilityBefore) * 1000000000000000000000000000;
    require formalBookForfeitedRemainder(assetA) < 1000000000000000000000000000;
    require to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
            + formalBookForfeitedRemainder(assetA) + scaledForfeiture
        < (to_mathint(max_uint256) + 1) * 1000000000000000000000000000;

    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 forfeitedBefore = formalBookTotalForfeited(assetA);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(assetA);

    syncOperator@withrevert(e, 1);
    assert !lastReverted, "valid zero-other-weight transfer must queue";

    assert syncedOwner(1) == currentOwner;
    assert syncedMultiplierBps(1) == currentMultiplier;
    mathint currentWeight = currentOwner == operatorVault() ? 0 : currentMultiplier;
    assert to_mathint(effectiveWeight(1)) == currentWeight;
    assert to_mathint(totalEffectiveWeight()) == currentWeight;
    assert formalBookIndex(assetA) == oldIndex;
    assert formalBookIndexRemainder(assetA) == oldIndexRemainder;
    assert formalAccrued(1, assetA) == 0 && formalSettlementRemainder(1, assetA) == 0;
    assert formalCheckpoint(1, assetA) == oldIndex;
    assert pendingOperatorRewards(1, assetA) == 0;
    assert formalPendingForfeitureRemainder(1, assetA) < 1000000000000000000000000000;
    assert to_mathint(formalPendingForfeitureAmount(1, assetA)) * 1000000000000000000000000000
            + formalPendingForfeitureRemainder(1, assetA)
        == scaledForfeiture;
    assert formalBookLiability(assetA) == liabilityBefore;
    assert formalBookTotalClaimed(assetA) == claimedBefore;
    assert to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
        + formalBookForfeitedRemainder(assetA)
        == to_mathint(forfeitedBefore) * 1000000000000000000000000000
            + forfeitedRemainderBefore + scaledForfeiture;
}

/// Flushing a queued forfeiture conserves scaled value and excludes its source Operator.
rule pendingForfeitureFlushConservesAndExcludesSource(env e) {
    address assetA = rewardA();
    uint256 sourceWeight = effectiveWeight(1);
    uint256 totalWeightBefore = totalEffectiveWeight();
    mathint denominator = to_mathint(totalWeightBefore) - sourceWeight;

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require syncedMultiplierBps(1) >= 10000 && syncedMultiplierBps(1) <= 12500;
    require (syncedOwner(1) == operatorVault() && sourceWeight == 0)
        || (syncedOwner(1) != operatorVault() && sourceWeight == syncedMultiplierBps(1));
    require totalWeightBefore > sourceWeight && totalWeightBefore <= 37500;
    require denominator >= 10000;
    require rewardAssetCount() == 1 && rewardAssetAt(0) == assetA && isRewardAsset(assetA);

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldIndexRemainder = formalBookIndexRemainder(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    uint256 pendingAmount = formalPendingForfeitureAmount(1, assetA);
    uint256 pendingRemainder = formalPendingForfeitureRemainder(1, assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    require oldIndexRemainder < 37500;
    require pendingRemainder < 1000000000000000000000000000;
    require pendingAmount > 0 || pendingRemainder > 0;
    require liabilityBefore <= 79228162514264337593543950335;

    mathint sourceScaled = to_mathint(sourceWeight) * (oldIndex - oldCheckpoint)
        + oldSettlementRemainder;
    mathint redistributionNumerator = to_mathint(pendingAmount) * 1000000000000000000000000000
        + pendingRemainder + oldIndexRemainder;
    // The settled source state and its queued forfeiture are both terms of the
    // same live-liability conservation identity.
    require to_mathint(oldAccrued) * 1000000000000000000000000000
            + sourceScaled
            + to_mathint(pendingAmount) * 1000000000000000000000000000
            + pendingRemainder
        <= to_mathint(liabilityBefore) * 1000000000000000000000000000;
    require redistributionNumerator <= max_uint256;
    require redistributionNumerator
        < (to_mathint(max_uint256) - oldIndex + 1) * denominator;

    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 forfeitedBefore = formalBookTotalForfeited(assetA);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(assetA);

    flushPendingForfeiture@withrevert(e, 1, assetA);
    assert !lastReverted, "valid queued forfeiture flush must succeed";

    assert formalPendingForfeitureAmount(1, assetA) == 0;
    assert formalPendingForfeitureRemainder(1, assetA) == 0;
    assert formalCheckpoint(1, assetA) == formalBookIndex(assetA);
    assert formalSettlementRemainder(1, assetA) < 1000000000000000000000000000;
    assert to_mathint(formalAccrued(1, assetA)) * 1000000000000000000000000000
            + formalSettlementRemainder(1, assetA)
        == to_mathint(oldAccrued) * 1000000000000000000000000000 + sourceScaled;
    assert (to_mathint(formalBookIndex(assetA)) - oldIndex) * denominator
        + formalBookIndexRemainder(assetA) == redistributionNumerator;
    assert formalBookLiability(assetA) == liabilityBefore;
    assert formalBookTotalClaimed(assetA) == claimedBefore;
    assert formalBookTotalForfeited(assetA) == forfeitedBefore;
    assert formalBookForfeitedRemainder(assetA) == forfeitedRemainderBefore;
}

/// A vault-held zero interval earns nothing before the Operator exits the vault.
rule vaultExitStartsAfterZeroInterval(env e) {
    address assetA = rewardA();
    address currentOwner = system.ownerOf(1);
    uint16 currentMultiplier = system.multiplierBps(1);
    uint256 totalWeightBefore = totalEffectiveWeight();

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require syncedOwner(1) == operatorVault();
    require syncedMultiplierBps(1) >= 10000 && syncedMultiplierBps(1) <= 12500;
    require effectiveWeight(1) == 0;
    require currentOwner != 0 && currentOwner != operatorVault();
    require currentMultiplier >= 10000 && currentMultiplier <= 12500;
    require to_mathint(totalWeightBefore) + currentMultiplier <= 37500;
    require rewardAssetCount() == 1 && rewardAssetAt(0) == assetA && isRewardAsset(assetA);

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldIndexRemainder = formalBookIndexRemainder(assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require liabilityBefore <= 79228162514264337593543950335;
    require oldIndex >= formalCheckpoint(1, assetA);
    require formalAccrued(1, assetA) == 0;
    require formalSettlementRemainder(1, assetA) == 0;

    syncOperator@withrevert(e, 1);
    assert !lastReverted, "valid vault exit must succeed";

    assert syncedOwner(1) == currentOwner;
    assert syncedMultiplierBps(1) == currentMultiplier;
    assert effectiveWeight(1) == currentMultiplier;
    assert to_mathint(totalEffectiveWeight()) == to_mathint(totalWeightBefore) + currentMultiplier;
    assert formalBookIndex(assetA) == oldIndex;
    assert formalBookIndexRemainder(assetA) == oldIndexRemainder;
    assert formalCheckpoint(1, assetA) == oldIndex;
    assert formalAccrued(1, assetA) == 0;
    assert formalSettlementRemainder(1, assetA) == 0;
    assert pendingOperatorRewards(1, assetA) == 0;
    assert formalBookLiability(assetA) == liabilityBefore;
}

/// A claim-triggered activation pays only the entitlement earned at the old weight.
rule claimTriggeredActivationPaysOldWeight(env e, address receiver) {
    address assetA = rewardA();
    address owner = syncedOwner(1);
    uint256 oldWeight = effectiveWeight(1);
    uint16 oldMultiplier = syncedMultiplierBps(1);
    uint16 currentMultiplier = system.multiplierBps(1);
    uint256 totalWeightBefore = totalEffectiveWeight();

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require system.ownerOf(1) == owner;
    require owner != 0 && owner != operatorVault() && owner != currentContract;
    require e.msg.sender == owner;
    require receiver != 0 && receiver != currentContract;
    require oldWeight == oldMultiplier;
    require oldMultiplier >= 10000;
    require currentMultiplier > oldMultiplier && currentMultiplier <= 12500;
    require totalWeightBefore >= oldWeight && totalWeightBefore <= 37500;
    require to_mathint(totalWeightBefore) - oldWeight + currentMultiplier <= 37500;
    require rewardAssetCount() == 1 && rewardAssetAt(0) == assetA && isRewardAsset(assetA);

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    mathint scaled = to_mathint(oldWeight) * (oldIndex - oldCheckpoint) + oldSettlementRemainder;
    mathint completeScaled =
        to_mathint(oldAccrued) * 1000000000000000000000000000 + scaled;
    // The complete pre-claim entitlement is bounded by live liability conservation.
    require liabilityBefore <= 79228162514264337593543950335;
    require completeScaled <= to_mathint(liabilityBefore) * 1000000000000000000000000000;
    require completeScaled >= 1000000000000000000000000000;

    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 routerBalanceBefore = tokenA.balanceOf(currentContract);
    uint256 receiverBalanceBefore = tokenA.balanceOf(receiver);
    require completeScaled
        < (to_mathint(routerBalanceBefore) + 1) * 1000000000000000000000000000;
    require completeScaled
        < (to_mathint(max_uint256) - claimedBefore + 1) * 1000000000000000000000000000;
    require completeScaled
        < (to_mathint(max_uint256) - receiverBalanceBefore + 1) * 1000000000000000000000000000;

    uint256 claimed = claimOperatorRewards@withrevert(e, 1, assetA, receiver);
    assert !lastReverted, "valid claim-triggered activation must succeed";

    assert formalSettlementRemainder(1, assetA) < 1000000000000000000000000000;
    assert to_mathint(claimed) * 1000000000000000000000000000
            + formalSettlementRemainder(1, assetA)
        == completeScaled;
    assert syncedOwner(1) == owner;
    assert syncedMultiplierBps(1) == currentMultiplier;
    assert effectiveWeight(1) == currentMultiplier;
    assert to_mathint(totalEffectiveWeight())
        == to_mathint(totalWeightBefore) - oldWeight + currentMultiplier;
    assert formalCheckpoint(1, assetA) == oldIndex;
    assert formalAccrued(1, assetA) == 0;
    assert to_mathint(formalBookTotalClaimed(assetA)) == to_mathint(claimedBefore) + claimed;
    assert to_mathint(formalBookLiability(assetA)) == to_mathint(liabilityBefore) - claimed;
    assert to_mathint(tokenA.balanceOf(currentContract))
        == to_mathint(routerBalanceBefore) - claimed;
    assert to_mathint(tokenA.balanceOf(receiver))
        == to_mathint(receiverBalanceBefore) + claimed;
}

/// A second unchanged claim cannot pay the same settled entitlement twice.
rule noDoubleClaim(env e, address receiver) {
    address assetA = rewardA();
    address owner = syncedOwner(1);
    uint256 oldWeight = effectiveWeight(1);
    uint256 totalWeightBefore = totalEffectiveWeight();

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require system.ownerOf(1) == owner;
    require system.multiplierBps(1) == syncedMultiplierBps(1);
    require owner != 0 && owner != operatorVault() && owner != currentContract;
    require e.msg.sender == owner;
    require receiver != 0 && receiver != currentContract;
    require oldWeight == syncedMultiplierBps(1);
    require oldWeight >= 10000 && oldWeight <= 12500;
    require totalWeightBefore >= oldWeight && totalWeightBefore <= 37500;
    require rewardAssetCount() == 1 && rewardAssetAt(0) == assetA && isRewardAsset(assetA);

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    mathint scaled = to_mathint(oldWeight) * (oldIndex - oldCheckpoint) + oldSettlementRemainder;
    mathint completeScaled =
        to_mathint(oldAccrued) * 1000000000000000000000000000 + scaled;
    // The complete pre-claim entitlement is bounded by live liability conservation.
    require liabilityBefore <= 79228162514264337593543950335;
    require completeScaled <= to_mathint(liabilityBefore) * 1000000000000000000000000000;
    require completeScaled >= 1000000000000000000000000000;

    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 routerBalanceBefore = tokenA.balanceOf(currentContract);
    uint256 receiverBalanceBefore = tokenA.balanceOf(receiver);
    require completeScaled
        < (to_mathint(routerBalanceBefore) + 1) * 1000000000000000000000000000;
    require completeScaled
        < (to_mathint(max_uint256) - claimedBefore + 1) * 1000000000000000000000000000;
    require completeScaled
        < (to_mathint(max_uint256) - receiverBalanceBefore + 1) * 1000000000000000000000000000;

    uint256 firstClaim = claimOperatorRewards@withrevert(e, 1, assetA, receiver);
    assert !lastReverted, "first exact claim must succeed";
    assert formalSettlementRemainder(1, assetA) < 1000000000000000000000000000;
    assert to_mathint(firstClaim) * 1000000000000000000000000000
            + formalSettlementRemainder(1, assetA)
        == completeScaled;

    uint256 claimedAfterFirst = formalBookTotalClaimed(assetA);
    uint256 liabilityAfterFirst = formalBookLiability(assetA);
    uint256 routerBalanceAfterFirst = tokenA.balanceOf(currentContract);
    uint256 receiverBalanceAfterFirst = tokenA.balanceOf(receiver);
    uint256 checkpointAfterFirst = formalCheckpoint(1, assetA);
    uint256 remainderAfterFirst = formalSettlementRemainder(1, assetA);

    claimOperatorRewards@withrevert(e, 1, assetA, receiver);
    assert lastReverted, "second unchanged claim must revert with no rewards";
    assert formalBookTotalClaimed(assetA) == claimedAfterFirst;
    assert formalBookLiability(assetA) == liabilityAfterFirst;
    assert tokenA.balanceOf(currentContract) == routerBalanceAfterFirst;
    assert tokenA.balanceOf(receiver) == receiverBalanceAfterFirst;
    assert formalCheckpoint(1, assetA) == checkpointAfterFirst;
    assert formalSettlementRemainder(1, assetA) == remainderAfterFirst;
    assert formalAccrued(1, assetA) == 0;
}

/// A current owner can trigger transfer synchronization, but receives none of the former owner's entitlement.
rule claimTriggeredTransferPersistsAndPaysZero(env e, address receiver) {
    address assetA = rewardA();
    address previousOwner = syncedOwner(1);
    address currentOwner = system.ownerOf(1);
    uint16 currentMultiplier = system.multiplierBps(1);
    uint256 oldWeight = effectiveWeight(1);
    uint256 totalWeightBefore = totalEffectiveWeight();
    mathint denominator = to_mathint(totalWeightBefore) - oldWeight;

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require previousOwner != 0 && previousOwner != operatorVault();
    require currentOwner != 0 && currentOwner != previousOwner;
    require currentOwner != operatorVault() && currentOwner != currentContract;
    require e.msg.sender == currentOwner;
    require receiver != 0 && receiver != currentContract;
    require currentMultiplier >= 10000 && currentMultiplier <= 12500;
    require oldWeight == syncedMultiplierBps(1);
    require oldWeight >= 10000 && oldWeight <= 12500;
    require totalWeightBefore > oldWeight && totalWeightBefore <= 37500;
    require denominator >= 10000;
    require rewardAssetCount() == 1 && rewardAssetAt(0) == assetA && isRewardAsset(assetA);

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldIndexRemainder = formalBookIndexRemainder(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    require oldIndexRemainder < 37500;
    require liabilityBefore <= 79228162514264337593543950335;

    mathint scaledForfeiture = to_mathint(oldAccrued) * 1000000000000000000000000000
        + to_mathint(oldWeight) * (oldIndex - oldCheckpoint) + oldSettlementRemainder;
    mathint redistributionNumerator = scaledForfeiture + oldIndexRemainder;
    // This forfeited entitlement is one nonnegative term of live liability conservation.
    require scaledForfeiture > 0;
    require scaledForfeiture
        <= to_mathint(liabilityBefore) * 1000000000000000000000000000;
    require redistributionNumerator <= max_uint256;
    require formalBookForfeitedRemainder(assetA) < 1000000000000000000000000000;
    require redistributionNumerator
        < (to_mathint(max_uint256) - oldIndex + 1) * denominator;
    require to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
            + formalBookForfeitedRemainder(assetA) + scaledForfeiture
        < (to_mathint(max_uint256) + 1) * 1000000000000000000000000000;

    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 forfeitedBefore = formalBookTotalForfeited(assetA);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(assetA);
    uint256 routerBalanceBefore = tokenA.balanceOf(currentContract);
    uint256 receiverBalanceBefore = tokenA.balanceOf(receiver);

    uint256 claimed = claimOperatorRewards@withrevert(e, 1, assetA, receiver);
    assert !lastReverted, "current owner transfer claim must synchronize";

    assert claimed == 0;
    assert syncedOwner(1) == currentOwner;
    assert syncedMultiplierBps(1) == currentMultiplier;
    assert effectiveWeight(1) == currentMultiplier;
    assert to_mathint(totalEffectiveWeight())
        == to_mathint(totalWeightBefore) - oldWeight + currentMultiplier;
    assert formalAccrued(1, assetA) == 0 && formalSettlementRemainder(1, assetA) == 0;
    assert formalCheckpoint(1, assetA) == formalBookIndex(assetA);
    assert pendingOperatorRewards(1, assetA) == 0;
    assert formalBookLiability(assetA) == liabilityBefore;
    assert formalBookTotalClaimed(assetA) == claimedBefore;
    assert tokenA.balanceOf(currentContract) == routerBalanceBefore;
    assert tokenA.balanceOf(receiver) == receiverBalanceBefore;
    assert to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
        + formalBookForfeitedRemainder(assetA)
        == to_mathint(forfeitedBefore) * 1000000000000000000000000000
            + forfeitedRemainderBefore + scaledForfeiture;
    assert (to_mathint(formalBookIndex(assetA)) - oldIndex) * denominator
        + formalBookIndexRemainder(assetA) == redistributionNumerator;
}

/// A former owner cannot claim after canonical ownership changes, and the reverted sync leaves state unchanged.
rule formerOwnerCannotClaimAfterCanonicalTransfer(env e, address receiver) {
    address assetA = rewardA();
    address previousOwner = syncedOwner(1);
    address currentOwner = system.ownerOf(1);
    uint16 currentMultiplier = system.multiplierBps(1);
    uint256 oldWeight = effectiveWeight(1);
    uint256 totalWeightBefore = totalEffectiveWeight();
    mathint denominator = to_mathint(totalWeightBefore) - oldWeight;

    require e.msg.value == 0;
    require !formalReentrancyGuardEntered();
    require formalOperatorInitialized(1);
    require previousOwner != 0 && previousOwner != operatorVault() && previousOwner != currentContract;
    require currentOwner != 0 && currentOwner != previousOwner;
    require e.msg.sender == previousOwner;
    require receiver != 0 && receiver != currentContract;
    require currentMultiplier >= 10000 && currentMultiplier <= 12500;
    require oldWeight == syncedMultiplierBps(1);
    require oldWeight >= 10000 && oldWeight <= 12500;
    require totalWeightBefore > oldWeight && totalWeightBefore <= 37500;
    require denominator >= 10000;
    require rewardAssetCount() == 1 && rewardAssetAt(0) == assetA && isRewardAsset(assetA);

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldIndexRemainder = formalBookIndexRemainder(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    require oldIndexRemainder < 37500;
    require liabilityBefore <= 79228162514264337593543950335;

    mathint scaledForfeiture = to_mathint(oldAccrued) * 1000000000000000000000000000
        + to_mathint(oldWeight) * (oldIndex - oldCheckpoint) + oldSettlementRemainder;
    mathint redistributionNumerator = scaledForfeiture + oldIndexRemainder;
    // The reverted transition is constrained to a reachable entitlement so the
    // proof reaches the former-owner authorization check instead of arithmetic failure.
    require scaledForfeiture
        <= to_mathint(liabilityBefore) * 1000000000000000000000000000;
    require redistributionNumerator <= max_uint256;
    require formalBookForfeitedRemainder(assetA) < 1000000000000000000000000000;
    require redistributionNumerator
        < (to_mathint(max_uint256) - oldIndex + 1) * denominator;
    require to_mathint(formalBookTotalForfeited(assetA)) * 1000000000000000000000000000
            + formalBookForfeitedRemainder(assetA) + scaledForfeiture
        < (to_mathint(max_uint256) + 1) * 1000000000000000000000000000;

    uint256 checkpointBefore = formalCheckpoint(1, assetA);
    uint256 remainderBefore = formalSettlementRemainder(1, assetA);
    uint256 accruedBefore = formalAccrued(1, assetA);
    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 forfeitedBefore = formalBookTotalForfeited(assetA);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(assetA);
    uint256 pendingBefore = formalPendingForfeitureAmount(1, assetA);
    uint256 pendingRemainderBefore = formalPendingForfeitureRemainder(1, assetA);
    uint256 routerBalanceBefore = tokenA.balanceOf(currentContract);
    uint256 receiverBalanceBefore = tokenA.balanceOf(receiver);

    claimOperatorRewards@withrevert(e, 1, assetA, receiver);
    assert lastReverted, "former owner claim must revert";

    assert syncedOwner(1) == previousOwner;
    assert effectiveWeight(1) == oldWeight;
    assert totalEffectiveWeight() == totalWeightBefore;
    assert formalBookIndex(assetA) == oldIndex;
    assert formalBookIndexRemainder(assetA) == oldIndexRemainder;
    assert formalCheckpoint(1, assetA) == checkpointBefore;
    assert formalSettlementRemainder(1, assetA) == remainderBefore;
    assert formalAccrued(1, assetA) == accruedBefore;
    assert formalBookLiability(assetA) == liabilityBefore;
    assert formalBookTotalClaimed(assetA) == claimedBefore;
    assert formalBookTotalForfeited(assetA) == forfeitedBefore;
    assert formalBookForfeitedRemainder(assetA) == forfeitedRemainderBefore;
    assert formalPendingForfeitureAmount(1, assetA) == pendingBefore;
    assert formalPendingForfeitureRemainder(1, assetA) == pendingRemainderBefore;
    assert tokenA.balanceOf(currentContract) == routerBalanceBefore;
    assert tokenA.balanceOf(receiver) == receiverBalanceBefore;
}
