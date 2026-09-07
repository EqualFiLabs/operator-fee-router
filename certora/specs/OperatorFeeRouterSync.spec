using FormalOperatorSystem as system;

methods {
    function rewardA() external returns (address) envfree;
    function operatorVault() external returns (address) envfree;
    function rewardAssetCount() external returns (uint256) envfree;
    function rewardAssetAt(uint256) external returns (address) envfree;
    function isRewardAsset(address) external returns (bool) envfree;
    function totalEffectiveWeight() external returns (uint256) envfree;
    function syncedOwner(uint256) external returns (address) envfree;
    function syncedMultiplierBps(uint256) external returns (uint16) envfree;
    function effectiveWeight(uint256) external returns (uint256) envfree;
    function formalOperatorInitialized(uint256) external returns (bool) envfree;
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
}

/// Raising a multiplier settles a registered asset at the old weight, then installs the new weight prospectively.
rule activationSettlesAtOldWeight(env e) {
    address assetA = rewardA();
    uint256 oldWeight = effectiveWeight(1);
    uint16 oldMultiplier = syncedMultiplierBps(1);
    uint16 newMultiplier = system.multiplierBps(1);
    uint256 totalWeightBefore = totalEffectiveWeight();

    require e.msg.value == 0;
    require formalOperatorInitialized(1);
    require system.ownerOf(1) == syncedOwner(1);
    require syncedOwner(1) != operatorVault();
    require oldWeight == oldMultiplier;
    require oldMultiplier >= 10000;
    require newMultiplier > oldMultiplier && newMultiplier <= 12500;
    require totalWeightBefore >= oldWeight && totalWeightBefore <= 37500;
    require rewardAssetCount() == 1;
    require rewardAssetAt(0) == assetA;
    require isRewardAsset(assetA);

    uint256 indexA = formalBookIndex(assetA);
    uint256 checkpointA = formalCheckpoint(1, assetA);
    uint256 remainderA = formalSettlementRemainder(1, assetA);
    uint256 accruedA = formalAccrued(1, assetA);
    require indexA >= checkpointA;
    require remainderA < 1000000000000000000000000000;
    mathint scaledA = to_mathint(oldWeight) * (indexA - checkpointA) + remainderA;
    require scaledA <= max_uint256;
    require to_mathint(accruedA) + scaledA / 1000000000000000000000000000 <= max_uint256;

    uint256 liabilityA = formalBookLiability(assetA);

    syncOperator(e, 1);

    assert syncedOwner(1) == system.ownerOf(1);
    assert syncedMultiplierBps(1) == newMultiplier;
    assert effectiveWeight(1) == newMultiplier;
    assert to_mathint(totalEffectiveWeight())
        == to_mathint(totalWeightBefore) - oldWeight + newMultiplier,
        "activation must replace exactly one stored weight";
    assert formalCheckpoint(1, assetA) == indexA;
    assert to_mathint(formalAccrued(1, assetA)) == to_mathint(accruedA)
        + scaledA / 1000000000000000000000000000,
        "asset A must settle at the old weight";
    assert formalSettlementRemainder(1, assetA)
        == scaledA % 1000000000000000000000000000;
    assert formalBookLiability(assetA) == liabilityA;
}

/// A same-owner multiplier decrease is deliberately treated as a forfeiting transfer transition.
rule lowerMultiplierUsesTransferSemantics(env e) {
    uint256 oldWeight = effectiveWeight(1);
    uint16 oldMultiplier = syncedMultiplierBps(1);
    uint16 currentMultiplier = system.multiplierBps(1);
    uint256 totalWeightBefore = totalEffectiveWeight();

    require e.msg.value == 0;
    require formalOperatorInitialized(1);
    require rewardAssetCount() == 0;
    require system.ownerOf(1) == syncedOwner(1);
    require syncedOwner(1) != operatorVault();
    require oldWeight == oldMultiplier;
    require oldMultiplier <= 12500;
    require currentMultiplier >= 10000 && currentMultiplier < oldMultiplier;
    require totalWeightBefore >= oldWeight && totalWeightBefore <= 37500;

    syncOperator(e, 1);

    assert syncedOwner(1) == system.ownerOf(1);
    assert syncedMultiplierBps(1) == currentMultiplier;
    assert effectiveWeight(1) == currentMultiplier;
    assert to_mathint(totalEffectiveWeight())
        == to_mathint(totalWeightBefore) - oldWeight + currentMultiplier,
        "decrease must remove the old weight and install the lower canonical weight";
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
    require formalOperatorInitialized(1);
    require previousOwner != 0 && previousOwner != operatorVault();
    require currentOwner != 0 && currentOwner != previousOwner;
    require currentMultiplier >= 10000 && currentMultiplier <= 12500;
    require oldWeight == syncedMultiplierBps(1);
    require oldWeight >= 10000 && oldWeight <= 12500;
    require totalWeightBefore > oldWeight && totalWeightBefore <= 37500;
    require rewardAssetCount() == 1;
    require rewardAssetAt(0) == assetA;
    require isRewardAsset(assetA);

    uint256 oldIndex = formalBookIndex(assetA);
    uint256 oldIndexRemainder = formalBookIndexRemainder(assetA);
    uint256 oldCheckpoint = formalCheckpoint(1, assetA);
    uint256 oldSettlementRemainder = formalSettlementRemainder(1, assetA);
    uint256 oldAccrued = formalAccrued(1, assetA);
    require oldIndex >= oldCheckpoint;
    require oldSettlementRemainder < 1000000000000000000000000000;
    require oldIndexRemainder < 37500;
    require oldAccrued <= 79228162514264337593543950335;
    require oldAccrued <= formalBookLiability(assetA);

    mathint scaledForfeiture = to_mathint(oldAccrued) * 1000000000000000000000000000
        + to_mathint(oldWeight) * (oldIndex - oldCheckpoint) + oldSettlementRemainder;
    mathint forfeitedAmount = scaledForfeiture / 1000000000000000000000000000;
    mathint forfeitedRemainder = scaledForfeiture % 1000000000000000000000000000;
    mathint redistributionNumerator = forfeitedAmount * 1000000000000000000000000000
        + forfeitedRemainder + oldIndexRemainder;
    mathint indexDelta = redistributionNumerator / denominator;

    require scaledForfeiture <= max_uint256;
    require forfeitedAmount <= 79228162514264337593543950335;
    require redistributionNumerator <= max_uint256;
    require to_mathint(oldIndex) + indexDelta <= max_uint256;
    require to_mathint(formalBookTotalForfeited(assetA)) + forfeitedAmount + 1 <= max_uint256;
    require formalBookForfeitedRemainder(assetA) < 1000000000000000000000000000;

    uint256 addedBefore = formalBookTotalAdded(assetA);
    uint256 claimedBefore = formalBookTotalClaimed(assetA);
    uint256 liabilityBefore = formalBookLiability(assetA);
    uint256 forfeitedBefore = formalBookTotalForfeited(assetA);
    uint256 forfeitedRemainderBefore = formalBookForfeitedRemainder(assetA);
    uint256 pendingBefore = formalPendingForfeitureAmount(1, assetA);
    uint256 pendingRemainderBefore = formalPendingForfeitureRemainder(1, assetA);

    syncOperator(e, 1);

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
