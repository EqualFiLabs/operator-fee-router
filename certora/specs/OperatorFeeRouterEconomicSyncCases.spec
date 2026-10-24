import "OperatorFeeRouterEconomicSyncById.spec";

// Disjoint, exhaustive partition of _syncOperator's canonical transition.
// 0: noop; 1: same-owner increase; 2: same-owner decrease;
// 3: enters vault; 4: leaves vault; 5: other ownership change.
// Each case retains symbolic registry membership/order, both assets, remainders,
// amounts, canonical multipliers, and all three installed Operator weights.
function classifyEconomicSync(
    address previousOwner,
    address currentOwner,
    uint16 previousMultiplier,
    uint16 currentMultiplier,
    address vault
) returns uint256 {
    if (currentOwner == previousOwner) {
        if (currentMultiplier == previousMultiplier) return 0;
        if (currentMultiplier > previousMultiplier) return 1;
        return 2;
    }
    if (currentOwner == vault) return 3;
    if (previousOwner == vault) return 4;
    return 5;
}

// Straight-line case predicates let the selected literal kind simplify before
// execution. The classifier rule checks their equivalence independently.
function economicSyncCaseMatches(
    address previousOwner,
    address currentOwner,
    uint16 previousMultiplier,
    uint16 currentMultiplier,
    address vault,
    uint256 kind
) returns bool {
    bool sameOwner = currentOwner == previousOwner;
    return (kind == 0 && sameOwner && currentMultiplier == previousMultiplier)
        || (kind == 1 && sameOwner && currentMultiplier > previousMultiplier)
        || (kind == 2 && sameOwner && currentMultiplier < previousMultiplier)
        || (kind == 3 && !sameOwner && currentOwner == vault)
        || (kind == 4 && !sameOwner && currentOwner != vault && previousOwner == vault)
        || (kind == 5 && !sameOwner && currentOwner != vault && previousOwner != vault);
}

function otherWeightedCheckpoints(uint256 id, address asset) returns mathint {
    if (id == 1) return weightedCheckpoint(2, asset) + weightedCheckpoint(3, asset);
    if (id == 2) return weightedCheckpoint(1, asset) + weightedCheckpoint(3, asset);
    return weightedCheckpoint(1, asset) + weightedCheckpoint(2, asset);
}

function otherRecordedEntitlements(uint256 id, address asset) returns mathint {
    if (id == 1) return recordedScaledEntitlement(2, asset) + recordedScaledEntitlement(3, asset);
    if (id == 2) return recordedScaledEntitlement(1, asset) + recordedScaledEntitlement(3, asset);
    return recordedScaledEntitlement(1, asset) + recordedScaledEntitlement(2, asset);
}

// This helper adds checked intermediate equalities for the existing Activation
// case. Every assertion is a prerequisite of the final conservation assertion.
function executeEconomicActivation(env e, uint256 id, address asset) {
    uint16 previousWeight = currentContract.operatorState[id].effectiveWeight;
    uint16 newWeight = system.ownerOf(id) == currentContract.operatorVault ? 0 : system.multiplierBps(id);
    uint256 previousTotalWeight = currentContract.totalEffectiveWeight;
    uint256 previousIndex = currentContract.rewardBook[asset].indexRay;
    uint256 previousIndexRemainder = currentContract.rewardBook[asset].indexRemainder;
    uint256 previousLiability = currentContract.rewardBook[asset].accountedLiability;
    uint256 previousCheckpoint = currentContract.operatorAssetState[id][asset].checkpointRay;
    mathint previousRecorded = recordedScaledEntitlement(id, asset);
    mathint previousOtherCheckpoints = otherWeightedCheckpoints(id, asset);
    mathint previousOtherRecorded = otherRecordedEntitlements(id, asset);
    mathint replacementTotal = to_mathint(previousTotalWeight) - previousWeight + newWeight;
    mathint replacementIndexProduct = replacementTotal * previousIndex;

    // Prove pure distribution before executing storage updates. After the call,
    // equality of the installed aggregate transfers this exact product by congruence.
    assert replacementIndexProduct
        == to_mathint(previousTotalWeight) * previousIndex
            - to_mathint(previousWeight) * previousIndex
            + to_mathint(newWeight) * previousIndex,
        "the precomputed replacement weight distributes over the existing index";

    syncOperator(e, id);

    assert currentContract.operatorState[id].effectiveWeight == newWeight,
        "activation installs the canonical effective weight";
    assert to_mathint(currentContract.totalEffectiveWeight)
        == replacementTotal,
        "activation replaces only the selected weight in the aggregate";

    // Retired assets are outside the guarded economic identity and are not settled.
    // Fresh unregistered assets retain their invariant-required zero state.
    if (!rewardAssetIsDeregistered(asset)) {
        assert currentContract.rewardBook[asset].indexRay == previousIndex
            && currentContract.rewardBook[asset].indexRemainder == previousIndexRemainder
            && currentContract.rewardBook[asset].accountedLiability == previousLiability,
            "activation leaves the asset index remainder and liability unchanged";
        assert currentContract.operatorAssetState[id][asset].checkpointRay == previousIndex,
            "activation checkpoints the selected asset at its existing index";
        assert recordedScaledEntitlement(id, asset)
            == previousRecorded
                + to_mathint(previousWeight) * (to_mathint(previousIndex) - previousCheckpoint),
            "activation converts exactly the selected unsettled entitlement into recorded rewards";
        assert otherWeightedCheckpoints(id, asset) == previousOtherCheckpoints,
            "activation leaves other Operators weighted checkpoints unchanged";
        assert otherRecordedEntitlements(id, asset) == previousOtherRecorded,
            "activation leaves other Operators recorded entitlements unchanged";
        assert to_mathint(currentContract.totalEffectiveWeight) * previousIndex == replacementIndexProduct,
            "the installed aggregate has the precomputed replacement index product";
        assert to_mathint(currentContract.totalEffectiveWeight) * previousIndex
            == to_mathint(previousTotalWeight) * previousIndex
                - to_mathint(previousWeight) * previousIndex
                + to_mathint(newWeight) * previousIndex,
            "activation aggregate index product distributes over the weight replacement";
    }
}

// Independent symbolic inputs establish the meaning of every classifier value.
// Equality of bools checks both directions, including completeness of the union.
rule economicSyncCasePartitionIsExact(
    address previousOwner,
    address currentOwner,
    uint16 previousMultiplier,
    uint16 currentMultiplier,
    address vault
) {
    uint256 kind = classifyEconomicSync(
        previousOwner, currentOwner, previousMultiplier, currentMultiplier, vault
    );
    bool sameOwner = currentOwner == previousOwner;
    assert kind <= 5;
    assert economicSyncCaseMatches(
        previousOwner, currentOwner, previousMultiplier, currentMultiplier, vault, kind
    ), "the classifier selects a matching case";
    uint256 selectedKind;
    assert economicSyncCaseMatches(
        previousOwner, currentOwner, previousMultiplier, currentMultiplier, vault, selectedKind
    ) == (selectedKind == kind), "only the classified case matches";
    assert (kind == 0) == (sameOwner && currentMultiplier == previousMultiplier);
    assert (kind == 1) == (sameOwner && currentMultiplier > previousMultiplier);
    assert (kind == 2) == (sameOwner && currentMultiplier < previousMultiplier);
    assert (kind == 3) == (!sameOwner && currentOwner == vault);
    assert (kind == 4) == (!sameOwner && currentOwner != vault && previousOwner == vault);
    assert (kind == 5) == (!sameOwner && currentOwner != vault && previousOwner != vault);
}

function proveEconomicSyncCase(env e, uint256 id, uint256 kind, address asset) {
    require economicSyncCaseMatches(
        currentContract.operatorState[id].syncedOwner,
        system.ownerOf(id),
        currentContract.operatorState[id].syncedMultiplierBps,
        system.multiplierBps(id),
        currentContract.operatorVault,
        kind
    );
    requireEconomicSyncPrestate(id);

    // Both paths execute the complete production sync over both assets.
    if (kind == 1) {
        executeEconomicActivation(e, id, asset);
    } else {
        syncOperator(e, id);
    }

    assert (isKnownRewardAsset(asset) && !rewardAssetIsDeregistered(asset))
        => balancedEconomicIdentity(asset),
        "sync case must preserve the selected asset's economic conservation";
}

rule economicSyncCaseNoopId1AssetA(env e) {
    proveEconomicSyncCase(e, 1, 0, currentContract.rewardA);
}

rule economicSyncCaseNoopId1AssetB(env e) {
    proveEconomicSyncCase(e, 1, 0, currentContract.rewardB);
}

rule economicSyncCaseNoopId2AssetA(env e) {
    proveEconomicSyncCase(e, 2, 0, currentContract.rewardA);
}

rule economicSyncCaseNoopId2AssetB(env e) {
    proveEconomicSyncCase(e, 2, 0, currentContract.rewardB);
}

rule economicSyncCaseNoopId3AssetA(env e) {
    proveEconomicSyncCase(e, 3, 0, currentContract.rewardA);
}

rule economicSyncCaseNoopId3AssetB(env e) {
    proveEconomicSyncCase(e, 3, 0, currentContract.rewardB);
}

rule economicSyncCaseActivationId1AssetA(env e) {
    proveEconomicSyncCase(e, 1, 1, currentContract.rewardA);
}

rule economicSyncCaseActivationId1AssetB(env e) {
    proveEconomicSyncCase(e, 1, 1, currentContract.rewardB);
}

rule economicSyncCaseActivationId2AssetA(env e) {
    proveEconomicSyncCase(e, 2, 1, currentContract.rewardA);
}

rule economicSyncCaseActivationId2AssetB(env e) {
    proveEconomicSyncCase(e, 2, 1, currentContract.rewardB);
}

rule economicSyncCaseActivationId3AssetA(env e) {
    proveEconomicSyncCase(e, 3, 1, currentContract.rewardA);
}

rule economicSyncCaseActivationId3AssetB(env e) {
    proveEconomicSyncCase(e, 3, 1, currentContract.rewardB);
}

rule economicSyncCaseDecreaseId1AssetA(env e) {
    proveEconomicSyncCase(e, 1, 2, currentContract.rewardA);
}

rule economicSyncCaseDecreaseId1AssetB(env e) {
    proveEconomicSyncCase(e, 1, 2, currentContract.rewardB);
}

rule economicSyncCaseDecreaseId2AssetA(env e) {
    proveEconomicSyncCase(e, 2, 2, currentContract.rewardA);
}

rule economicSyncCaseDecreaseId2AssetB(env e) {
    proveEconomicSyncCase(e, 2, 2, currentContract.rewardB);
}

rule economicSyncCaseDecreaseId3AssetA(env e) {
    proveEconomicSyncCase(e, 3, 2, currentContract.rewardA);
}

rule economicSyncCaseDecreaseId3AssetB(env e) {
    proveEconomicSyncCase(e, 3, 2, currentContract.rewardB);
}

rule economicSyncCaseEnterVaultId1AssetA(env e) {
    proveEconomicSyncCase(e, 1, 3, currentContract.rewardA);
}

rule economicSyncCaseEnterVaultId1AssetB(env e) {
    proveEconomicSyncCase(e, 1, 3, currentContract.rewardB);
}

rule economicSyncCaseEnterVaultId2AssetA(env e) {
    proveEconomicSyncCase(e, 2, 3, currentContract.rewardA);
}

rule economicSyncCaseEnterVaultId2AssetB(env e) {
    proveEconomicSyncCase(e, 2, 3, currentContract.rewardB);
}

rule economicSyncCaseEnterVaultId3AssetA(env e) {
    proveEconomicSyncCase(e, 3, 3, currentContract.rewardA);
}

rule economicSyncCaseEnterVaultId3AssetB(env e) {
    proveEconomicSyncCase(e, 3, 3, currentContract.rewardB);
}

rule economicSyncCaseLeaveVaultId1AssetA(env e) {
    proveEconomicSyncCase(e, 1, 4, currentContract.rewardA);
}

rule economicSyncCaseLeaveVaultId1AssetB(env e) {
    proveEconomicSyncCase(e, 1, 4, currentContract.rewardB);
}

rule economicSyncCaseLeaveVaultId2AssetA(env e) {
    proveEconomicSyncCase(e, 2, 4, currentContract.rewardA);
}

rule economicSyncCaseLeaveVaultId2AssetB(env e) {
    proveEconomicSyncCase(e, 2, 4, currentContract.rewardB);
}

rule economicSyncCaseLeaveVaultId3AssetA(env e) {
    proveEconomicSyncCase(e, 3, 4, currentContract.rewardA);
}

rule economicSyncCaseLeaveVaultId3AssetB(env e) {
    proveEconomicSyncCase(e, 3, 4, currentContract.rewardB);
}

rule economicSyncCaseOwnerChangeId1AssetA(env e) {
    proveEconomicSyncCase(e, 1, 5, currentContract.rewardA);
}

rule economicSyncCaseOwnerChangeId1AssetB(env e) {
    proveEconomicSyncCase(e, 1, 5, currentContract.rewardB);
}

rule economicSyncCaseOwnerChangeId2AssetA(env e) {
    proveEconomicSyncCase(e, 2, 5, currentContract.rewardA);
}

rule economicSyncCaseOwnerChangeId2AssetB(env e) {
    proveEconomicSyncCase(e, 2, 5, currentContract.rewardB);
}

rule economicSyncCaseOwnerChangeId3AssetA(env e) {
    proveEconomicSyncCase(e, 3, 5, currentContract.rewardA);
}

rule economicSyncCaseOwnerChangeId3AssetB(env e) {
    proveEconomicSyncCase(e, 3, 5, currentContract.rewardB);
}
