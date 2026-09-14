// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {IActivationRegistry} from "../src/interfaces/IActivationRegistry.sol";
import {IOperatorCollection} from "../src/interfaces/IOperatorCollection.sol";
import {MockAuthority} from "./mocks/MockOperatorSystem.sol";
import {MockERC20} from "./mocks/MockTokens.sol";

interface IForkOperatorCollection is IOperatorCollection {
    function getTransferValidator() external view returns (address validator);
    function locked(uint256 operatorId) external view returns (bool);
    function transferFrom(address from, address to, uint256 operatorId) external;
}

interface IForkActivationRegistry is IActivationRegistry {
    function statics() external view returns (address);
    function treasury() external view returns (address);
    function tierOf(uint256 operatorId) external view returns (uint8);
    function tierCost(uint8 tier) external view returns (uint256);
    function activate(uint256 operatorId, uint8 targetTier) external returns (uint256 paid);
}

contract OperatorFeeRouterForkTest is Test {
    struct BookSnapshot {
        uint256 indexRay;
        uint256 indexRemainder;
        uint256 totalAdded;
        uint256 totalClaimed;
        uint256 liability;
        uint256 totalForfeited;
        uint256 totalForfeitedRemainder;
        bool registered;
        bool depositsEnabled;
    }

    uint256 internal constant PINNED_BLOCK = 56_931_136;
    address internal constant OPERATOR_COLLECTION = 0xad5E9F96A91D1A6F550580b157af2068A0e8F0BE;
    address internal constant ACTIVATION_REGISTRY = 0xfC62e99CaE93878f83801f3d6Bb4f1762E720B30;
    address internal constant OPERATOR_VAULT = 0x8AAAF9a22f439589987B8f1e69d79ca4f648C297;
    address internal constant STATICS = 0x2d8d6F4A93AcD7a916A5a654ec8b690bA3B3EAdd;

    bytes32 internal constant OPERATOR_COLLECTION_CODE_HASH =
        0x4999fbcee14596c8105be151c80a8f7f2ae2c75e48d869cd8f4003a59f7f8085;
    bytes32 internal constant ACTIVATION_REGISTRY_CODE_HASH =
        0xfcbf8ede9f8f15ff097f344c24d0751d9a23d7b49856e16066ab44caa635bffa;
    bytes32 internal constant OPERATOR_VAULT_CODE_HASH =
        0x6d027e43d02497d10f651ada60a51f9fbf41b718dd416a1467c3050b99b9bec4;
    bytes32 internal constant STATICS_CODE_HASH = 0xf10f86b05965a827a332e6c73086f18026fbe3917f4bffbec3f938b3b5397b56;

    bool internal forkEnabled;
    IOperatorCollection internal collection;
    IActivationRegistry internal registry;
    IForkOperatorCollection internal forkCollection;
    IForkActivationRegistry internal forkRegistry;
    MockAuthority internal timelock;
    OperatorFeeRouter internal router;

    function setUp() public {
        forkEnabled = vm.envExists("ROBINHOOD_MAINNET");
        if (!forkEnabled) {
            vm.skip(true, "ROBINHOOD_MAINNET is not configured");
        }

        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET"), PINNED_BLOCK);
        collection = IOperatorCollection(OPERATOR_COLLECTION);
        registry = IActivationRegistry(ACTIVATION_REGISTRY);
        forkCollection = IForkOperatorCollection(OPERATOR_COLLECTION);
        forkRegistry = IForkActivationRegistry(ACTIVATION_REGISTRY);
        timelock = new MockAuthority();
        router = new OperatorFeeRouter(OPERATOR_COLLECTION, ACTIVATION_REGISTRY, OPERATOR_VAULT, address(timelock));
    }

    function testFork_CanonicalBindingsMatchRouterImmutables() public view {
        assertEq(block.chainid, 4_663);
        assertEq(collection.COLLECTION_SIZE(), 5_555);
        assertEq(collection.vault(), OPERATOR_VAULT);
        assertEq(collection.activationRegistry(), ACTIVATION_REGISTRY);
        assertEq(registry.genesisCollection(), OPERATOR_COLLECTION);
        assertEq(address(router.operatorCollection()), OPERATOR_COLLECTION);
        assertEq(address(router.activationRegistry()), ACTIVATION_REGISTRY);
        assertEq(router.operatorVault(), OPERATOR_VAULT);
        assertEq(forkRegistry.statics(), STATICS);
        assertEq(OPERATOR_COLLECTION.codehash, OPERATOR_COLLECTION_CODE_HASH);
        assertEq(ACTIVATION_REGISTRY.codehash, ACTIVATION_REGISTRY_CODE_HASH);
        assertEq(OPERATOR_VAULT.codehash, OPERATOR_VAULT_CODE_HASH);
        assertEq(STATICS.codehash, STATICS_CODE_HASH);
    }

    function testFork_FirstBootstrapBatchMatchesPinnedCanonicalState() public {
        uint256 expectedWeight;
        for (uint256 operatorId = 1; operatorId <= 100; ++operatorId) {
            if (collection.ownerOf(operatorId) != OPERATOR_VAULT) {
                expectedWeight += registry.multiplierBps(operatorId);
            }
        }

        router.bootstrapOperators(100);
        assertEq(router.nextOperatorId(), 101);
        assertEq(router.totalEffectiveWeight(), expectedWeight);

        (address firstOwner, uint16 firstMultiplier, uint16 firstWeight, bool initialized) = router.operatorState(1);
        assertEq(firstOwner, collection.ownerOf(1));
        assertEq(firstMultiplier, registry.multiplierBps(1));
        assertEq(firstWeight, firstOwner == OPERATOR_VAULT ? 0 : firstMultiplier);
        assertTrue(initialized);
    }

    function testFork_FullCanonicalLifecycleWhenExplicitlyEnabled() public {
        if (!vm.envOr("RUN_FULL_ROUTER_FORK", false)) {
            vm.skip(true, "set RUN_FULL_ROUTER_FORK=true for the release-gate lifecycle");
        }

        uint256 initialTotalWeight = _bootstrapAndAssertEveryOperator();
        _assertLifecyclePreconditions();

        MockERC20 reward = new MockERC20("Fork Reward", "FRWD");
        vm.prank(address(timelock));
        router.registerRewardAsset(address(reward));
        _addRewards(reward, initialTotalWeight);
        (uint256 activatedTotalWeight, address operatorTwoOwner) = _activateOperatorTwo(reward, initialTotalWeight);
        _transferOperatorOneAndReconcile(reward, initialTotalWeight, activatedTotalWeight, operatorTwoOwner);
    }

    function _assertLifecyclePreconditions() internal view {
        assertTrue(collection.ownerOf(1) != OPERATOR_VAULT);
        assertTrue(collection.ownerOf(2) != OPERATOR_VAULT);
        assertEq(forkRegistry.tierOf(1), 4);
        assertEq(forkRegistry.tierOf(2), 0);
        assertEq(registry.multiplierBps(1), 12_500);
        assertEq(registry.multiplierBps(2), 10_000);
        assertFalse(forkCollection.locked(1));
        assertFalse(forkCollection.locked(2));
        assertEq(forkCollection.getTransferValidator(), address(0));
    }

    function _activateOperatorTwo(MockERC20 reward, uint256 initialTotalWeight)
        internal
        returns (uint256 activatedTotalWeight, address operatorTwoOwner)
    {
        operatorTwoOwner = collection.ownerOf(2);
        assertEq(router.pendingOperatorRewards(1, address(reward)), 12_500);
        assertEq(router.pendingOperatorRewards(2, address(reward)), 10_000);

        uint256 activationCost = forkRegistry.tierCost(1);
        uint256 treasuryBefore = IERC20(STATICS).balanceOf(forkRegistry.treasury());
        deal(STATICS, operatorTwoOwner, activationCost);
        vm.startPrank(operatorTwoOwner);
        IERC20(STATICS).approve(ACTIVATION_REGISTRY, activationCost);
        assertEq(forkRegistry.activate(2, 1), activationCost);
        vm.stopPrank();

        assertEq(IERC20(STATICS).balanceOf(forkRegistry.treasury()), treasuryBefore + activationCost);
        assertEq(forkRegistry.tierOf(2), 1);
        assertEq(registry.multiplierBps(2), 11_000);
        assertEq(router.syncedMultiplierBps(2), 10_000);
        assertEq(uint8(router.syncOperator(2)), uint8(OperatorFeeRouter.SyncKind.Activation));

        activatedTotalWeight = initialTotalWeight - 10_000 + 11_000;
        assertEq(router.totalEffectiveWeight(), activatedTotalWeight);
        _addRewards(reward, activatedTotalWeight);
        assertEq(router.pendingOperatorRewards(1, address(reward)), 25_000);
        assertEq(router.pendingOperatorRewards(2, address(reward)), 21_000);
    }

    function _transferOperatorOneAndReconcile(
        MockERC20 reward,
        uint256 initialTotalWeight,
        uint256 activatedTotalWeight,
        address operatorTwoOwner
    ) internal {
        address operatorOneOwner = collection.ownerOf(1);
        address newOperatorOneOwner = makeAddr("fork-new-operator-one-owner");
        vm.prank(operatorOneOwner);
        forkCollection.transferFrom(operatorOneOwner, newOperatorOneOwner, 1);
        assertEq(collection.ownerOf(1), newOperatorOneOwner);
        assertEq(forkRegistry.tierOf(1), 0);
        assertEq(registry.multiplierBps(1), 10_000);
        assertEq(router.syncedOwner(1), operatorOneOwner);
        assertEq(router.syncedMultiplierBps(1), 12_500);
        assertEq(router.pendingOperatorRewards(1, address(reward)), 0);

        _addRewards(reward, activatedTotalWeight);
        BookSnapshot memory beforeBook = _bookSnapshot(address(reward));
        uint256 totalWeightBeforeTransferSync = router.totalEffectiveWeight();
        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Transfer));
        assertEq(router.totalEffectiveWeight(), totalWeightBeforeTransferSync - 12_500 + 10_000);
        assertEq(router.syncedOwner(1), newOperatorOneOwner);
        assertEq(router.syncedMultiplierBps(1), 10_000);
        assertEq(router.effectiveWeight(1), 10_000);
        assertEq(router.pendingOperatorRewards(1, address(reward)), 0);

        BookSnapshot memory afterBook = _bookSnapshot(address(reward));
        assertEq(afterBook.totalAdded, beforeBook.totalAdded);
        assertEq(afterBook.totalClaimed, beforeBook.totalClaimed);
        assertEq(afterBook.liability, beforeBook.liability);
        assertEq(afterBook.totalForfeited, 37_500);

        uint256 operatorTwoClaim = router.pendingOperatorRewards(2, address(reward));
        assertGt(operatorTwoClaim, 32_000);
        vm.prank(operatorTwoOwner);
        assertEq(router.claimOperatorRewards(2, address(reward), operatorTwoOwner), operatorTwoClaim);
        assertEq(reward.balanceOf(operatorTwoOwner), operatorTwoClaim);

        BookSnapshot memory finalBook = _bookSnapshot(address(reward));
        assertEq(finalBook.totalAdded, initialTotalWeight + activatedTotalWeight * 2);
        assertEq(finalBook.totalClaimed, operatorTwoClaim);
        assertEq(finalBook.liability, finalBook.totalAdded - finalBook.totalClaimed);
        assertEq(reward.balanceOf(address(router)), finalBook.liability);
        assertEq(router.availableSurplus(address(reward)), 0);
    }

    function _bootstrapAndAssertEveryOperator() internal returns (uint256 expectedTotalWeight) {
        for (uint256 i; i < 56; ++i) {
            router.bootstrapOperators(100);
        }
        router.finalizeBootstrap();
        assertEq(router.nextOperatorId(), 5_556);
        assertTrue(router.bootstrapFinalized());

        for (uint256 operatorId = 1; operatorId <= 5_555; ++operatorId) {
            address canonicalOwner = collection.ownerOf(operatorId);
            uint16 canonicalMultiplier = registry.multiplierBps(operatorId);
            uint16 canonicalWeight = canonicalOwner == OPERATOR_VAULT ? 0 : canonicalMultiplier;
            (address owner, uint16 multiplier, uint16 weight, bool initialized) = router.operatorState(operatorId);
            assertTrue(initialized);
            assertEq(owner, canonicalOwner);
            assertEq(multiplier, canonicalMultiplier);
            assertEq(weight, canonicalWeight);
            expectedTotalWeight += canonicalWeight;
        }
        assertEq(router.totalEffectiveWeight(), expectedTotalWeight);
    }

    function _addRewards(MockERC20 reward, uint256 amount) internal {
        reward.mint(address(this), amount);
        reward.approve(address(router), amount);
        router.addRewards(address(reward), amount);
    }

    function _bookSnapshot(address asset) internal view returns (BookSnapshot memory book) {
        (bool success, bytes memory returndata) =
            address(router).staticcall(abi.encodeWithSignature("rewardBook(address)", asset));
        require(success, "reward book read failed");
        book = abi.decode(returndata, (BookSnapshot));
    }
}
