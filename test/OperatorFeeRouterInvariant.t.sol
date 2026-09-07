// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {MockActivationRegistry, MockAuthority, MockOperatorCollection, MockVault} from "./mocks/MockOperatorSystem.sol";
import {MockERC20} from "./mocks/MockTokens.sol";
import {OperatorFeeRouterHarness} from "./mocks/OperatorFeeRouterHarness.sol";

contract OperatorFeeRouterHandler is Test {
    uint256 internal constant OPERATOR_COUNT = 8;
    uint256 internal constant ASSET_COUNT = 3;

    OperatorFeeRouterHarness public immutable router;
    MockOperatorCollection public immutable collection;
    MockActivationRegistry public immutable registry;
    address public immutable timelock;
    address public immutable vault;

    MockERC20[ASSET_COUNT] internal _tokens;
    address[OPERATOR_COUNT + 1] internal _owners;

    mapping(address asset => uint256 amount) public ghostAdded;
    mapping(address asset => uint256 amount) public ghostClaimed;
    mapping(address asset => uint256 amount) public ghostDonated;
    mapping(address asset => uint256 amount) public ghostRecovered;

    constructor(
        OperatorFeeRouterHarness router_,
        MockOperatorCollection collection_,
        MockActivationRegistry registry_,
        MockERC20[ASSET_COUNT] memory tokens_,
        address timelock_,
        address vault_
    ) {
        router = router_;
        collection = collection_;
        registry = registry_;
        _tokens = tokens_;
        timelock = timelock_;
        vault = vault_;

        for (uint256 i; i < OPERATOR_COUNT; ++i) {
            _owners[i] = makeAddr(string.concat("handler-owner-", vm.toString(i + 1)));
        }
        _owners[OPERATOR_COUNT] = vault_;
    }

    function tokenAt(uint256 index) external view returns (MockERC20) {
        return _tokens[index];
    }

    function addRewards(uint256 rawAsset, uint128 rawAmount) external {
        MockERC20 token = _token(rawAsset);
        if (!router.rewardAssetEnabled(address(token)) || router.totalEffectiveWeight() == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, 1e24);
        token.mint(address(this), amount);
        token.approve(address(router), amount);
        router.addRewards(address(token), amount);
        ghostAdded[address(token)] += amount;
    }

    function activate(uint256 rawOperatorId, uint256 rawTier) external {
        uint256 operatorId = _operatorId(rawOperatorId);
        if (collection.ownerOf(operatorId) == vault) return;

        uint16 current = registry.multiplierBps(operatorId);
        uint16[5] memory tiers = [uint16(10_000), 11_000, 11_500, 12_000, 12_500];
        uint256 firstHigher;
        while (firstHigher < tiers.length && tiers[firstHigher] <= current) ++firstHigher;
        if (firstHigher == tiers.length) return;

        registry.setMultiplier(operatorId, tiers[bound(rawTier, firstHigher, tiers.length - 1)]);
    }

    function transfer(uint256 rawOperatorId, uint256 rawOwner) external {
        uint256 operatorId = _operatorId(rawOperatorId);
        address nextOwner = _owners[bound(rawOwner, 0, _owners.length - 1)];
        if (nextOwner == collection.ownerOf(operatorId)) return;

        collection.setOwner(operatorId, nextOwner);
        registry.setMultiplier(operatorId, 10_000);
    }

    function sync(uint256 rawOperatorId) external {
        uint256 operatorId = _operatorId(rawOperatorId);
        (address previousOwner, uint16 previousMultiplier, uint16 previousWeight,) = router.operatorState(operatorId);
        address currentOwner = collection.ownerOf(operatorId);
        uint16 currentMultiplier = registry.multiplierBps(operatorId);
        uint16 currentWeight = currentOwner == vault ? 0 : currentMultiplier;
        uint256 totalWeightBefore = router.totalEffectiveWeight();

        OperatorFeeRouter.SyncKind expectedKind =
            _expectedKind(previousOwner, previousMultiplier, currentOwner, currentMultiplier);
        OperatorFeeRouter.SyncKind actualKind = router.syncOperator(operatorId);
        assertEq(uint8(actualKind), uint8(expectedKind));
        _assertInstalledState(operatorId, currentOwner, currentMultiplier, currentWeight);
        assertEq(router.totalEffectiveWeight(), totalWeightBefore - previousWeight + currentWeight);

        if (actualKind == OperatorFeeRouter.SyncKind.Transfer) {
            _assertTransferCleared(operatorId);
        }
    }

    function claim(uint256 rawOperatorId, uint256 rawAsset) external {
        uint256 operatorId = _operatorId(rawOperatorId);
        address asset = address(_token(rawAsset));
        address currentOwner = collection.ownerOf(operatorId);
        if (currentOwner == vault) return;

        (address previousOwner, uint16 previousMultiplier,,) = router.operatorState(operatorId);
        uint16 currentMultiplier = registry.multiplierBps(operatorId);
        bool snapshotChanged = currentOwner != previousOwner || currentMultiplier != previousMultiplier;
        if (!snapshotChanged && router.pendingOperatorRewards(operatorId, asset) == 0) return;

        vm.prank(currentOwner);
        uint256 amount = router.claimOperatorRewards(operatorId, asset, currentOwner);
        ghostClaimed[asset] += amount;
    }

    function donate(uint256 rawAsset, uint128 rawAmount) external {
        MockERC20 token = _token(rawAsset);
        uint256 amount = bound(uint256(rawAmount), 1, 1e24);
        token.mint(address(router), amount);
        ghostDonated[address(token)] += amount;
    }

    function recoverSurplus(uint256 rawAsset, uint128 rawAmount) external {
        address asset = address(_token(rawAsset));
        uint256 surplus = router.availableSurplus(asset);
        if (surplus == 0) return;

        uint256 amount = bound(uint256(rawAmount), 1, surplus);
        vm.prank(timelock);
        router.recoverSurplus(asset, address(this), amount);
        ghostRecovered[asset] += amount;
    }

    function flush(uint256 rawOperatorId, uint256 rawAsset) external {
        uint256 operatorId = _operatorId(rawOperatorId);
        address asset = address(_token(rawAsset));
        (uint256 pendingAmount, uint256 pendingRemainder) = router.pendingForfeiture(operatorId, asset);
        if (pendingAmount == 0 && pendingRemainder == 0) return;

        (,, uint16 weight,) = router.operatorState(operatorId);
        if (router.totalEffectiveWeight() == weight) return;
        router.flushPendingForfeiture(operatorId, asset);
    }

    function setAssetEnabled(uint256 rawAsset, bool enabled) external {
        address asset = address(_token(rawAsset));
        vm.prank(timelock);
        router.setRewardAssetEnabled(asset, enabled);
    }

    function _operatorId(uint256 rawOperatorId) internal pure returns (uint256) {
        return bound(rawOperatorId, 1, OPERATOR_COUNT);
    }

    function _token(uint256 rawAsset) internal view returns (MockERC20) {
        return _tokens[bound(rawAsset, 0, ASSET_COUNT - 1)];
    }

    function _expectedKind(
        address previousOwner,
        uint16 previousMultiplier,
        address currentOwner,
        uint16 currentMultiplier
    ) internal pure returns (OperatorFeeRouter.SyncKind) {
        if (currentOwner == previousOwner && currentMultiplier == previousMultiplier) {
            return OperatorFeeRouter.SyncKind.Noop;
        }
        if (currentOwner == previousOwner && currentMultiplier > previousMultiplier) {
            return OperatorFeeRouter.SyncKind.Activation;
        }
        return OperatorFeeRouter.SyncKind.Transfer;
    }

    function _assertInstalledState(
        uint256 operatorId,
        address expectedOwner,
        uint16 expectedMultiplier,
        uint16 expectedWeight
    ) internal view {
        (address owner, uint16 multiplier, uint16 weight, bool initialized) = router.operatorState(operatorId);
        assertTrue(initialized);
        assertEq(owner, expectedOwner);
        assertEq(multiplier, expectedMultiplier);
        assertEq(weight, expectedWeight);
    }

    function _assertTransferCleared(uint256 operatorId) internal view {
        for (uint256 i; i < ASSET_COUNT; ++i) {
            address asset = address(_tokens[i]);
            (uint256 indexRay,,,,,,,,) = router.rewardBook(asset);
            (uint256 checkpointRay, uint256 settlementRemainderRay, uint256 accrued) =
                router.operatorAssetState(operatorId, asset);
            assertEq(checkpointRay, indexRay);
            assertEq(settlementRemainderRay, 0);
            assertEq(accrued, 0);
            assertEq(router.pendingOperatorRewards(operatorId, asset), 0);
        }
    }
}

contract OperatorFeeRouterInvariantTest is StdInvariant, Test {
    uint256 internal constant OPERATOR_COUNT = 8;
    uint256 internal constant ASSET_COUNT = 3;
    uint256 internal constant MAX_TOTAL_WEIGHT = OPERATOR_COUNT * 12_500;

    MockVault internal vault;
    MockAuthority internal timelock;
    MockOperatorCollection internal collection;
    MockActivationRegistry internal registry;
    OperatorFeeRouterHarness internal router;
    MockERC20[ASSET_COUNT] internal tokens;
    OperatorFeeRouterHandler internal handler;

    function setUp() public {
        vault = new MockVault();
        timelock = new MockAuthority();
        collection = new MockOperatorCollection(address(vault));
        registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));
        for (uint256 operatorId = 1; operatorId <= OPERATOR_COUNT; ++operatorId) {
            collection.setOwner(operatorId, makeAddr(string.concat("operator-", vm.toString(operatorId))));
        }

        router = new OperatorFeeRouterHarness(address(collection), address(registry), address(vault), address(timelock));
        router.bootstrapOperators(OPERATOR_COUNT);
        router.harnessFinalizeBootstrap();

        tokens[0] = new MockERC20("Invariant Reward A", "IRWDA");
        tokens[1] = new MockERC20("Invariant Reward B", "IRWDB");
        tokens[2] = new MockERC20("Invariant Reward C", "IRWDC");
        for (uint256 i; i < ASSET_COUNT; ++i) {
            vm.prank(address(timelock));
            router.registerRewardAsset(address(tokens[i]));
        }

        handler = new OperatorFeeRouterHandler(router, collection, registry, tokens, address(timelock), address(vault));
        targetContract(address(handler));
    }

    function invariant_PerAssetAccountingAndSolvency() public view {
        for (uint256 i; i < ASSET_COUNT; ++i) {
            MockERC20 token = tokens[i];
            address asset = address(token);
            (,, uint256 totalAdded, uint256 totalClaimed, uint256 liability,,,,) = router.rewardBook(asset);
            uint256 balance = token.balanceOf(address(router));

            assertEq(totalAdded, handler.ghostAdded(asset));
            assertEq(totalClaimed, handler.ghostClaimed(asset));
            assertEq(liability, totalAdded - totalClaimed);
            assertGe(balance, liability);
            assertEq(router.availableSurplus(asset), balance - liability);
            assertEq(
                balance + handler.ghostClaimed(asset) + handler.ghostRecovered(asset),
                handler.ghostAdded(asset) + handler.ghostDonated(asset)
            );
            assertEq(router.availableSurplus(asset), handler.ghostDonated(asset) - handler.ghostRecovered(asset));
        }
    }

    function invariant_TotalWeightEqualsStoredWeights() public view {
        uint256 summedWeight;
        for (uint256 operatorId = 1; operatorId <= OPERATOR_COUNT; ++operatorId) {
            (address owner, uint16 multiplier, uint16 weight, bool initialized) = router.operatorState(operatorId);
            assertTrue(initialized);
            assertEq(weight, owner == address(vault) ? 0 : multiplier);
            summedWeight += weight;
        }
        assertEq(router.totalEffectiveWeight(), summedWeight);
        assertLe(summedWeight, MAX_TOTAL_WEIGHT);
    }

    function invariant_RemaindersStayNormalized() public view {
        for (uint256 i; i < ASSET_COUNT; ++i) {
            address asset = address(tokens[i]);
            (, uint256 indexRemainder,,,,, uint256 forfeitedRemainder,,) = router.rewardBook(asset);
            assertLt(indexRemainder, MAX_TOTAL_WEIGHT);
            assertLt(forfeitedRemainder, router.RAY());

            for (uint256 operatorId = 1; operatorId <= OPERATOR_COUNT; ++operatorId) {
                (, uint256 settlementRemainder,) = router.operatorAssetState(operatorId, asset);
                (, uint256 pendingRemainder) = router.pendingForfeiture(operatorId, asset);
                assertLt(settlementRemainder, router.RAY());
                assertLt(pendingRemainder, router.RAY());
            }
        }
    }

    function invariant_AssetRegistryIsFixedAndIsolated() public view {
        assertEq(router.rewardAssetCount(), ASSET_COUNT);
        for (uint256 i; i < ASSET_COUNT; ++i) {
            address asset = address(tokens[i]);
            assertEq(router.rewardAssetAt(i), asset);
            assertTrue(router.isRewardAsset(asset));
            assertEq(address(handler.tokenAt(i)), asset);
        }
    }
}
