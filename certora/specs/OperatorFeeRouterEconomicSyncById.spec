import "OperatorFeeRouterEconomic.spec";

// The economic invariant only has a nontrivial predicate for rewardA and rewardB.
// Fixing the operator ID partitions the complete bounded sync domain into three rules.
function requireEconomicSyncPrestate(uint256 id) {
    require id >= 1 && id <= 3;
    requireInvariant installedWeightsMatchAggregate();
    requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
    requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
    requireInvariant freshAssetStateIsZero(currentContract.rewardA);
    requireInvariant freshAssetStateIsZero(currentContract.rewardB);
    requireInvariant accountingStateIsNormalized(currentContract.rewardA);
    requireInvariant accountingStateIsNormalized(currentContract.rewardB);
    requireInvariant rewardAssetsEconomicConservation(currentContract.rewardA);
    requireInvariant rewardAssetsEconomicConservation(currentContract.rewardB);
    assertNaturalIdentityAndCap(id, currentContract.rewardA);
    assertNaturalIdentityAndCap(id, currentContract.rewardB);
}

function proveEconomicSyncForId(env e, uint256 id) {
    requireEconomicSyncPrestate(id);
    syncOperator(e, id);

    assert
        (isKnownRewardAsset(currentContract.rewardA)
            && !rewardAssetIsDeregistered(currentContract.rewardA))
            => balancedEconomicIdentity(currentContract.rewardA),
        "sync must preserve reward A economic conservation";
    assert
        (isKnownRewardAsset(currentContract.rewardB)
            && !rewardAssetIsDeregistered(currentContract.rewardB))
            => balancedEconomicIdentity(currentContract.rewardB),
        "sync must preserve reward B economic conservation";
}

rule economicSyncOperatorId1(env e) {
    proveEconomicSyncForId(e, 1);
}

rule economicSyncOperatorId2(env e) {
    proveEconomicSyncForId(e, 2);
}

rule economicSyncOperatorId3(env e) {
    proveEconomicSyncForId(e, 3);
}
