using FormalOperatorSystem as system;
using FormalRewardTokenA as tokenA;
using FormalRewardTokenB as tokenB;

methods {
    function bootstrapFinalized() external returns (bool) envfree;
    // The harness constructor is already finalized. Halmos proves production bootstrap progression.
    function bootstrapOperators(uint256) external returns (uint256, uint256) => NONDET DELETE;
    function finalizeBootstrap() external => NONDET DELETE;

    function system.hasRole(bytes32, address) external returns (bool) envfree;
    function system.ownerOf(uint256) external returns (address) envfree;
    function system.multiplierBps(uint256) external returns (uint16) envfree;
    function tokenA.balanceOf(address) external returns (uint256) envfree;
    function tokenB.balanceOf(address) external returns (uint256) envfree;

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.decimals() external => DISPATCHER(true);

    // SafeERC20 assembly calls use the linked exact-token storage model.
    function _.safeTransfer(address token, address to, uint256 value) internal with(env e)
        => cvlSafeTransfer(executingContract, e, token, to, value) expect void;
    function _.safeTransferFrom(address token, address from, address to, uint256 value) internal with(env e)
        => cvlSafeTransferFrom(e, token, from, to, value) expect void;
}

function cvlSafeTransfer(address executing, env e, address token, address to, uint256 value) {
    bool success = token.transferFrom(e, executing, to, value);
    require success;
}

function cvlSafeTransferFrom(env e, address token, address from, address to, uint256 value) {
    bool success = token.transferFrom(e, from, to, value);
    require success;
}

function isKnownRewardAsset(address asset) returns bool {
    return asset == currentContract.rewardA || asset == currentContract.rewardB;
}

function isRegisteredRewardAsset(address asset) returns bool {
    return currentContract.rewardBook[asset].registered;
}

function rewardAssetDepositsEnabled(address asset) returns bool {
    return currentContract.rewardBook[asset].depositsEnabled;
}

function rewardAssetIsDeregistered(address asset) returns bool {
    return currentContract.isRewardAssetDeregistered[asset];
}

function registryAssetAtOrZero(uint256 index) returns address {
    if (index >= currentContract._rewardAssets.length) return 0;
    return currentContract._rewardAssets[index];
}

function registryContains(address asset) returns bool {
    return (currentContract._rewardAssets.length >= 1 && registryAssetAtOrZero(0) == asset)
        || (currentContract._rewardAssets.length == 2 && registryAssetAtOrZero(1) == asset);
}

// The scene contains three initialized Operators. Bootstrap is excluded by the method
// summaries. Calls that address an Operator are restricted to those scene IDs; invalid-ID
// rejection and real bootstrap progression are checked separately by Halmos.
function installedWeight(uint256 id) returns bool {
    return currentContract.operatorState[id].initialized
        && currentContract.operatorState[id].syncedMultiplierBps >= 10000
        && currentContract.operatorState[id].syncedMultiplierBps <= 12500
        && currentContract.operatorState[id].effectiveWeight
            == (
                currentContract.operatorState[id].syncedOwner == currentContract.operatorVault
                    ? 0
                    : currentContract.operatorState[id].syncedMultiplierBps
            );
}

function normalizedEntitlementAtIndex(uint256 id, address asset, uint256 index) returns bool {
    return currentContract.operatorAssetState[id][asset].checkpointRay <= index
        && currentContract.operatorAssetState[id][asset].settlementRemainderRay
            < 1000000000000000000000000000
        && currentContract.pendingForfeiture[id][asset].remainderRay
            < 1000000000000000000000000000;
}

function completeScaledEntitlementAtIndex(uint256 id, address asset, uint256 index) returns mathint {
    return to_mathint(currentContract.operatorAssetState[id][asset].accrued)
            * 1000000000000000000000000000
        + currentContract.operatorAssetState[id][asset].settlementRemainderRay
        + to_mathint(currentContract.pendingForfeiture[id][asset].amount)
            * 1000000000000000000000000000
        + currentContract.pendingForfeiture[id][asset].remainderRay
        + to_mathint(currentContract.operatorState[id].effectiveWeight)
            * (
                to_mathint(index)
                    - to_mathint(currentContract.operatorAssetState[id][asset].checkpointRay)
            );
}

function recordedScaledEntitlement(uint256 id, address asset) returns mathint {
    return to_mathint(currentContract.operatorAssetState[id][asset].accrued)
            * 1000000000000000000000000000
        + currentContract.operatorAssetState[id][asset].settlementRemainderRay
        + to_mathint(currentContract.pendingForfeiture[id][asset].amount)
            * 1000000000000000000000000000
        + currentContract.pendingForfeiture[id][asset].remainderRay;
}

function weightAtIndex(uint256 id, uint256 index) returns mathint {
    return to_mathint(currentContract.operatorState[id].effectiveWeight) * to_mathint(index);
}

function weightDeltaAtIndex(uint256 id, address asset, uint256 index) returns mathint {
    return to_mathint(currentContract.operatorState[id].effectiveWeight)
        * (
            to_mathint(index)
                - to_mathint(currentContract.operatorAssetState[id][asset].checkpointRay)
        );
}

function weightedCheckpoint(uint256 id, address asset) returns mathint {
    return to_mathint(currentContract.operatorState[id].effectiveWeight)
        * to_mathint(currentContract.operatorAssetState[id][asset].checkpointRay);
}

function aggregateScalesAtIndex(uint256 index) returns bool {
    return to_mathint(currentContract.totalEffectiveWeight) * to_mathint(index)
        == weightAtIndex(1, index) + weightAtIndex(2, index) + weightAtIndex(3, index);
}

function operatorDeltaReconstructs(uint256 id, address asset, uint256 index) returns bool {
    return weightDeltaAtIndex(id, asset, index) + weightedCheckpoint(id, asset)
        == weightAtIndex(id, index);
}

function unfactoredEconomicIdentity(address asset) returns bool {
    return to_mathint(currentContract.rewardBook[asset].accountedLiability)
            * 1000000000000000000000000000
        == to_mathint(currentContract.rewardBook[asset].indexRemainder)
            + completeScaledEntitlementAtIndex(1, asset, currentContract.rewardBook[asset].indexRay)
            + completeScaledEntitlementAtIndex(2, asset, currentContract.rewardBook[asset].indexRay)
            + completeScaledEntitlementAtIndex(3, asset, currentContract.rewardBook[asset].indexRay);
}

// Under installedWeightsMatchAggregate, this is algebraically equivalent to the natural
// complete-entitlement equation. Factoring the shared index matches _increaseIndex's denominator.
function balancedEconomicIdentity(address asset) returns bool {
    return to_mathint(currentContract.rewardBook[asset].accountedLiability)
            * 1000000000000000000000000000
            + weightedCheckpoint(1, asset)
            + weightedCheckpoint(2, asset)
            + weightedCheckpoint(3, asset)
        == to_mathint(currentContract.rewardBook[asset].indexRemainder)
            + to_mathint(currentContract.totalEffectiveWeight)
                * currentContract.rewardBook[asset].indexRay
            + recordedScaledEntitlement(1, asset)
            + recordedScaledEntitlement(2, asset)
            + recordedScaledEntitlement(3, asset);
}

function completeEntitlementWithinLiability(uint256 id, address asset) returns bool {
    return completeScaledEntitlementAtIndex(id, asset, currentContract.rewardBook[asset].indexRay)
        <= to_mathint(currentContract.rewardBook[asset].accountedLiability)
            * 1000000000000000000000000000;
}

function assertNaturalIdentityAndCap(uint256 id, address asset) {
    bool registered = isRegisteredRewardAsset(asset);
    uint256 index = currentContract.rewardBook[asset].indexRay;

    assert !registered || aggregateScalesAtIndex(index),
        "prestate aggregate weight must scale across the asset index";
    assert !registered || operatorDeltaReconstructs(1, asset, index),
        "prestate Operator 1 weighted delta must reconstruct";
    assert !registered || operatorDeltaReconstructs(2, asset, index),
        "prestate Operator 2 weighted delta must reconstruct";
    assert !registered || operatorDeltaReconstructs(3, asset, index),
        "prestate Operator 3 weighted delta must reconstruct";
    assert !registered || unfactoredEconomicIdentity(asset),
        "prestate natural economic identity must follow from the balanced form";
    assert !registered || completeEntitlementWithinLiability(id, asset),
        "prestate complete entitlement must remain within liability";
}

function operatorAssetStateIsZero(uint256 id, address asset) returns bool {
    return currentContract.operatorAssetState[id][asset].checkpointRay == 0
        && currentContract.operatorAssetState[id][asset].settlementRemainderRay == 0
        && currentContract.operatorAssetState[id][asset].accrued == 0
        && currentContract.pendingForfeiture[id][asset].amount == 0
        && currentContract.pendingForfeiture[id][asset].remainderRay == 0;
}

function freshBookStateIsZero(address asset) returns bool {
    return currentContract.rewardBook[asset].indexRay == 0
        && currentContract.rewardBook[asset].indexRemainder == 0
        && currentContract.rewardBook[asset].totalAdded == 0
        && currentContract.rewardBook[asset].totalClaimed == 0
        && currentContract.rewardBook[asset].accountedLiability == 0
        && currentContract.rewardBook[asset].totalForfeited == 0
        && currentContract.rewardBook[asset].totalForfeitedRemainderRay == 0;
}

function accountingStateNormalized(address asset) returns bool {
    return currentContract.rewardBook[asset].accountedLiability <= 79228162514264337593543950335
        && currentContract.rewardBook[asset].indexRemainder < 37500
        && currentContract.rewardBook[asset].totalForfeitedRemainderRay
            < 1000000000000000000000000000
        && normalizedEntitlementAtIndex(1, asset, currentContract.rewardBook[asset].indexRay)
        && normalizedEntitlementAtIndex(2, asset, currentContract.rewardBook[asset].indexRay)
        && normalizedEntitlementAtIndex(3, asset, currentContract.rewardBook[asset].indexRay)
        && (
            rewardAssetIsDeregistered(asset)
                => currentContract.rewardBook[asset].accountedLiability == 0
        );
}

// This proof deliberately bounds the reward-asset universe to the two linked exact tokens.
// The configuration binds rewardA and rewardB to different instantiated token contracts.
// Registration of either token remains part of the lifecycle; registration of a third token
// is covered by the production limit tests outside this bounded conservation scene.
invariant boundedRegistryMatchesMembership(address asset)
    currentContract._rewardAssets.length <= 2
        && (currentContract._rewardAssets.length >= 1
            => isKnownRewardAsset(registryAssetAtOrZero(0))
                && isRegisteredRewardAsset(registryAssetAtOrZero(0)))
        && (currentContract._rewardAssets.length == 2
            => isKnownRewardAsset(registryAssetAtOrZero(1))
                && isRegisteredRewardAsset(registryAssetAtOrZero(1))
                && registryAssetAtOrZero(0) != registryAssetAtOrZero(1))
        && (isRegisteredRewardAsset(asset) == registryContains(asset))
        && (rewardAssetIsDeregistered(asset) => !registryContains(asset))
        && (!isRegisteredRewardAsset(asset) => !rewardAssetDepositsEnabled(asset))
    {
        preserved registerRewardAsset(address registeredAsset) with (env e) {
            require isKnownRewardAsset(registeredAsset);
            requireInvariant boundedRegistryMatchesMembership(registeredAsset);
        }
        preserved deregisterRewardAsset(address retiredAsset) with (env e) {
            requireInvariant boundedRegistryMatchesMembership(retiredAsset);
        }
    }

// A never-registered asset has no hidden book, entitlement, forfeiture, or expiry state.
// This supplies the independent zero base needed when a linked token is first registered.
invariant freshAssetStateIsZero(address asset)
    (!isRegisteredRewardAsset(asset) && !rewardAssetIsDeregistered(asset))
        => !rewardAssetDepositsEnabled(asset)
            && currentContract.expiredRewards[asset] == 0
            && freshBookStateIsZero(asset)
            && operatorAssetStateIsZero(1, asset)
            && operatorAssetStateIsZero(2, asset)
            && operatorAssetStateIsZero(3, asset)
    {
        preserved with (env e) {
            requireInvariant boundedRegistryMatchesMembership(asset);
        }
    }

invariant installedWeightsMatchAggregate()
    installedWeight(1) && installedWeight(2) && installedWeight(3)
        && to_mathint(currentContract.totalEffectiveWeight)
            == to_mathint(currentContract.operatorState[1].effectiveWeight)
                + to_mathint(currentContract.operatorState[2].effectiveWeight)
                + to_mathint(currentContract.operatorState[3].effectiveWeight)
    {
        preserved with (env e) {
            require currentContract._rewardAssets.length <= 2;
        }
        preserved syncOperator(uint256 id) with (env e) {
            require id >= 1 && id <= 3;
            require currentContract._rewardAssets.length <= 2;
        }
        preserved claimOperatorRewards(uint256 id, address asset, address receiver) with (env e) {
            require id >= 1 && id <= 3;
            require currentContract._rewardAssets.length <= 2;
        }
        preserved flushPendingForfeiture(uint256 id, address asset) with (env e) {
            require id >= 1 && id <= 3;
            require currentContract._rewardAssets.length <= 2;
        }
    }

// Bounds and normalization are co-proved with the economic equation for methods that settle
// rewards. Retired assets retain historical per-Operator records, but their live liability expires.
invariant accountingStateIsNormalized(address asset)
    accountingStateNormalized(asset)
    {
        preserved with (env e) {
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(asset);
            requireInvariant freshAssetStateIsZero(asset);
        }
        preserved registerRewardAsset(address registeredAsset) with (env e) {
            require isKnownRewardAsset(registeredAsset);
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(asset);
            requireInvariant boundedRegistryMatchesMembership(registeredAsset);
            requireInvariant freshAssetStateIsZero(asset);
            requireInvariant freshAssetStateIsZero(registeredAsset);
        }
        preserved addRewards(address addedAsset, uint256 amount) with (env e) {
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(asset);
            requireInvariant boundedRegistryMatchesMembership(addedAsset);
            requireInvariant freshAssetStateIsZero(asset);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
        }
        preserved syncOperator(uint256 id) with (env e) {
            require id >= 1 && id <= 3;
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(asset);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
            requireInvariant freshAssetStateIsZero(asset);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardA);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardB);
            assertNaturalIdentityAndCap(id, currentContract.rewardA);
            assertNaturalIdentityAndCap(id, currentContract.rewardB);
        }
        preserved claimOperatorRewards(uint256 id, address claimedAsset, address receiver) with (env e) {
            require id >= 1 && id <= 3;
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(asset);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
            requireInvariant boundedRegistryMatchesMembership(claimedAsset);
            requireInvariant freshAssetStateIsZero(asset);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardA);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardB);
            assertNaturalIdentityAndCap(id, currentContract.rewardA);
            assertNaturalIdentityAndCap(id, currentContract.rewardB);
        }
        preserved flushPendingForfeiture(uint256 id, address flushedAsset) with (env e) {
            require id >= 1 && id <= 3;
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(asset);
            requireInvariant boundedRegistryMatchesMembership(flushedAsset);
            requireInvariant freshAssetStateIsZero(asset);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardA);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardB);
            assertNaturalIdentityAndCap(id, flushedAsset);
        }
        preserved pendingOperatorRewards(uint256 id, address queriedAsset) with (env e) {
            require id >= 1 && id <= 3;
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(asset);
            requireInvariant boundedRegistryMatchesMembership(queriedAsset);
            requireInvariant freshAssetStateIsZero(asset);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardA);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardB);
            assertNaturalIdentityAndCap(id, queriedAsset);
        }
    }

// Both linked reward assets are proved in one induction because synchronization iterates the
// complete registry. The balanced form aligns index changes with total effective weight.
invariant rewardAssetsEconomicConservation(address trackedAsset)
    (isKnownRewardAsset(trackedAsset) && !rewardAssetIsDeregistered(trackedAsset))
        => balancedEconomicIdentity(trackedAsset)
    {
        preserved with (env e) {
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
            requireInvariant freshAssetStateIsZero(currentContract.rewardA);
            requireInvariant freshAssetStateIsZero(currentContract.rewardB);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
        }
        preserved registerRewardAsset(address registeredAsset) with (env e) {
            require isKnownRewardAsset(registeredAsset);
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
            requireInvariant boundedRegistryMatchesMembership(registeredAsset);
            requireInvariant freshAssetStateIsZero(currentContract.rewardA);
            requireInvariant freshAssetStateIsZero(currentContract.rewardB);
            requireInvariant freshAssetStateIsZero(registeredAsset);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
        }
        preserved addRewards(address addedAsset, uint256 amount) with (env e) {
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
            requireInvariant boundedRegistryMatchesMembership(addedAsset);
            requireInvariant freshAssetStateIsZero(currentContract.rewardA);
            requireInvariant freshAssetStateIsZero(currentContract.rewardB);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
        }
        preserved syncOperator(uint256 id) with (env e) {
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
        preserved claimOperatorRewards(uint256 id, address claimedAsset, address receiver) with (env e) {
            require id >= 1 && id <= 3;
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
            requireInvariant boundedRegistryMatchesMembership(claimedAsset);
            requireInvariant freshAssetStateIsZero(currentContract.rewardA);
            requireInvariant freshAssetStateIsZero(currentContract.rewardB);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardA);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardB);
            assertNaturalIdentityAndCap(id, currentContract.rewardA);
            assertNaturalIdentityAndCap(id, currentContract.rewardB);
        }
        preserved flushPendingForfeiture(uint256 id, address flushedAsset) with (env e) {
            require id >= 1 && id <= 3;
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
            requireInvariant boundedRegistryMatchesMembership(flushedAsset);
            requireInvariant freshAssetStateIsZero(currentContract.rewardA);
            requireInvariant freshAssetStateIsZero(currentContract.rewardB);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardA);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardB);
            assertNaturalIdentityAndCap(id, flushedAsset);
        }
        preserved pendingOperatorRewards(uint256 id, address queriedAsset) with (env e) {
            require id >= 1 && id <= 3;
            requireInvariant installedWeightsMatchAggregate();
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardA);
            requireInvariant boundedRegistryMatchesMembership(currentContract.rewardB);
            requireInvariant boundedRegistryMatchesMembership(queriedAsset);
            requireInvariant freshAssetStateIsZero(currentContract.rewardA);
            requireInvariant freshAssetStateIsZero(currentContract.rewardB);
            requireInvariant accountingStateIsNormalized(currentContract.rewardA);
            requireInvariant accountingStateIsNormalized(currentContract.rewardB);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardA);
            requireInvariant rewardAssetsEconomicConservation(currentContract.rewardB);
            assertNaturalIdentityAndCap(id, queriedAsset);
        }
    }
