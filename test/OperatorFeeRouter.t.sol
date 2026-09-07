// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {MockActivationRegistry, MockAuthority, MockOperatorCollection, MockVault} from "./mocks/MockOperatorSystem.sol";
import {MockERC20, MockFeeToken, MockReentrantToken, MockSenderFeeToken} from "./mocks/MockTokens.sol";
import {OperatorFeeRouterHarness} from "./mocks/OperatorFeeRouterHarness.sol";

contract ConstructorCollectionMock {
    uint256 public immutable COLLECTION_SIZE;
    address public immutable vault;
    address public immutable activationRegistry;

    constructor(uint256 collectionSize, address vault_, address activationRegistry_) {
        COLLECTION_SIZE = collectionSize;
        vault = vault_;
        activationRegistry = activationRegistry_;
    }
}

contract ConstructorRegistryMock {
    address public immutable genesisCollection;

    constructor(address genesisCollection_) {
        genesisCollection = genesisCollection_;
    }
}

contract OperatorFeeRouterTest is Test {
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

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal contributor = makeAddr("contributor");
    address internal receiver = makeAddr("receiver");

    MockVault internal vault;
    MockAuthority internal timelock;
    MockOperatorCollection internal collection;
    MockActivationRegistry internal registry;
    OperatorFeeRouterHarness internal router;
    MockERC20 internal token;

    function setUp() public {
        vault = new MockVault();
        timelock = new MockAuthority();
        collection = new MockOperatorCollection(address(vault));
        registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));
        collection.setOwner(1, alice);
        collection.setOwner(2, bob);

        router = new OperatorFeeRouterHarness(address(collection), address(registry), address(vault), address(timelock));
        router.bootstrapOperators(2);
        router.harnessFinalizeBootstrap();

        token = new MockERC20("Reward", "RWD");
        _register(address(token));
    }

    function test_ConstructorRejectsMismatchedRegistry() public {
        MockActivationRegistry wrongRegistry = new MockActivationRegistry(address(collection));
        vm.expectRevert(
            abi.encodeWithSelector(
                OperatorFeeRouter.InvalidCollectionRegistry.selector, address(wrongRegistry), address(registry)
            )
        );
        new OperatorFeeRouterHarness(address(collection), address(wrongRegistry), address(vault), address(timelock));
    }

    function test_ConstructorRejectsZeroAndCodelessDependencies() public {
        vm.expectRevert(OperatorFeeRouter.ZeroAddress.selector);
        new OperatorFeeRouterHarness(address(0), address(registry), address(vault), address(timelock));

        address codeless = makeAddr("codeless");
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.AddressHasNoCode.selector, codeless));
        new OperatorFeeRouterHarness(codeless, address(registry), address(vault), address(timelock));
    }

    function test_ConstructorRejectsInconsistentCanonicalConfiguration() public {
        ConstructorRegistryMock validRegistry = new ConstructorRegistryMock(address(1));
        ConstructorCollectionMock wrongSize =
            new ConstructorCollectionMock(5_554, address(vault), address(validRegistry));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InvalidCollectionSize.selector, 5_554));
        new OperatorFeeRouterHarness(address(wrongSize), address(validRegistry), address(vault), address(timelock));

        ConstructorCollectionMock wrongVault = new ConstructorCollectionMock(5_555, address(1), address(validRegistry));
        vm.expectRevert(
            abi.encodeWithSelector(OperatorFeeRouter.InvalidCollectionVault.selector, address(vault), address(1))
        );
        new OperatorFeeRouterHarness(address(wrongVault), address(validRegistry), address(vault), address(timelock));

        ConstructorRegistryMock configuredRegistry = new ConstructorRegistryMock(address(1));
        ConstructorRegistryMock suppliedRegistry = new ConstructorRegistryMock(address(1));
        ConstructorCollectionMock wrongRegistry =
            new ConstructorCollectionMock(5_555, address(vault), address(configuredRegistry));
        vm.expectRevert(
            abi.encodeWithSelector(
                OperatorFeeRouter.InvalidCollectionRegistry.selector,
                address(suppliedRegistry),
                address(configuredRegistry)
            )
        );
        new OperatorFeeRouterHarness(
            address(wrongRegistry), address(suppliedRegistry), address(vault), address(timelock)
        );

        ConstructorRegistryMock wrongCollectionRegistry = new ConstructorRegistryMock(address(1));
        ConstructorCollectionMock canonicalCollection =
            new ConstructorCollectionMock(5_555, address(vault), address(wrongCollectionRegistry));
        vm.expectRevert(
            abi.encodeWithSelector(
                OperatorFeeRouter.InvalidRegistryCollection.selector, address(canonicalCollection), address(1)
            )
        );
        new OperatorFeeRouterHarness(
            address(canonicalCollection), address(wrongCollectionRegistry), address(vault), address(timelock)
        );
    }

    function test_BootstrapInitializesCanonicalWeightsAndFinalizes() public {
        MockOperatorCollection freshCollection = new MockOperatorCollection(address(vault));
        MockActivationRegistry freshRegistry = new MockActivationRegistry(address(freshCollection));
        freshCollection.bindActivationRegistry(address(freshRegistry));
        freshCollection.setOwner(1, alice);
        freshCollection.setOwner(2, bob);
        freshRegistry.setMultiplier(2, 12_500);

        OperatorFeeRouter fresh =
            new OperatorFeeRouter(address(freshCollection), address(freshRegistry), address(vault), address(timelock));
        for (uint256 i; i < 56; ++i) {
            fresh.bootstrapOperators(100);
        }
        assertEq(fresh.nextOperatorId(), 5_556);
        assertEq(fresh.totalEffectiveWeight(), 22_500);
        fresh.finalizeBootstrap();
        assertTrue(fresh.bootstrapFinalized());

        (address firstOwner, uint16 firstMultiplier, uint16 firstWeight, bool firstInitialized) = fresh.operatorState(1);
        assertEq(firstOwner, alice);
        assertEq(firstMultiplier, 10_000);
        assertEq(firstWeight, 10_000);
        assertTrue(firstInitialized);
        assertEq(fresh.syncedOwner(1), alice);
        assertEq(fresh.syncedMultiplierBps(1), 10_000);
        assertEq(fresh.effectiveWeight(1), 10_000);

        (address vaultOwner,, uint16 vaultWeight, bool vaultInitialized) = fresh.operatorState(5_555);
        assertEq(vaultOwner, address(vault));
        assertEq(vaultWeight, 0);
        assertTrue(vaultInitialized);
    }

    function test_BootstrapRejectsInvalidCountsAndEarlyFinalization() public {
        OperatorFeeRouterHarness fresh =
            new OperatorFeeRouterHarness(address(collection), address(registry), address(vault), address(timelock));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InvalidBootstrapCount.selector, 0));
        fresh.bootstrapOperators(0);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InvalidBootstrapCount.selector, 101));
        fresh.bootstrapOperators(101);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.BootstrapIncomplete.selector, 1));
        fresh.finalizeBootstrap();
    }

    function test_FinalizedBootstrapCannotBeRepeated() public {
        vm.expectRevert(OperatorFeeRouter.BootstrapAlreadyFinalized.selector);
        router.bootstrapOperators(1);
        vm.expectRevert(OperatorFeeRouter.BootstrapAlreadyFinalized.selector);
        router.finalizeBootstrap();
    }

    function test_AddRewardsIsPermissionlessAndWeighted() public {
        _add(token, 200 ether);
        assertEq(router.pendingOperatorRewards(1, address(token)), 100 ether);
        assertEq(router.pendingOperatorRewards(2, address(token)), 100 ether);
        assertEq(_liability(address(token)), 200 ether);
    }

    function test_AddRewardsRejectsBeforeBootstrapFinalization() public {
        OperatorFeeRouterHarness fresh =
            new OperatorFeeRouterHarness(address(collection), address(registry), address(vault), address(timelock));
        vm.prank(address(timelock));
        fresh.registerRewardAsset(address(token));
        token.mint(contributor, 1 ether);
        vm.startPrank(contributor);
        token.approve(address(fresh), 1 ether);
        vm.expectRevert(OperatorFeeRouter.BootstrapNotFinalized.selector);
        fresh.addRewards(address(token), 1 ether);
        vm.stopPrank();
    }

    function test_AddRewardsCapsOutstandingLiability() public {
        uint256 limit = router.MAX_OUTSTANDING_REWARD_UNITS();
        _add(token, limit);

        token.mint(contributor, 1);
        vm.startPrank(contributor);
        token.approve(address(router), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperatorFeeRouter.RewardLiabilityLimitExceeded.selector, address(token), limit, 1, limit
            )
        );
        router.addRewards(address(token), 1);
        vm.stopPrank();

        assertEq(_liability(address(token)), limit);
        assertEq(token.balanceOf(address(router)), limit);
    }

    function test_OnlyTimelockCanConfigureAssets() public {
        MockERC20 other = new MockERC20("Other", "OTHER");
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.Unauthorized.selector, address(this)));
        router.registerRewardAsset(address(other));

        vm.prank(address(timelock));
        router.setRewardAssetEnabled(address(token), false);
        assertFalse(router.rewardAssetEnabled(address(token)));

        token.mint(contributor, 1 ether);
        vm.startPrank(contributor);
        token.approve(address(router), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetDisabled.selector, address(token)));
        router.addRewards(address(token), 1 ether);
        vm.stopPrank();
    }

    function test_RewardAssetRegistrationRejectsDuplicateAndInvalidAssets() public {
        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetAlreadyRegistered.selector, address(token)));
        router.registerRewardAsset(address(token));

        vm.prank(address(timelock));
        vm.expectRevert(OperatorFeeRouter.ZeroAddress.selector);
        router.registerRewardAsset(address(0));

        address codeless = makeAddr("unregistered-codeless");
        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.AddressHasNoCode.selector, codeless));
        router.registerRewardAsset(codeless);
    }

    function test_UnregisteredAssetOperationsRevert() public {
        MockERC20 unregistered = new MockERC20("Unregistered", "NOPE");
        vm.prank(address(timelock));
        vm.expectRevert(
            abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotRegistered.selector, address(unregistered))
        );
        router.setRewardAssetEnabled(address(unregistered), false);

        vm.expectRevert(
            abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotRegistered.selector, address(unregistered))
        );
        router.pendingOperatorRewards(1, address(unregistered));
    }

    function test_AddRewardsRejectsZeroAmountAndZeroEffectiveWeight() public {
        vm.expectRevert(OperatorFeeRouter.ZeroAmount.selector);
        router.addRewards(address(token), 0);

        collection.setOwner(1, address(vault));
        collection.setOwner(2, address(vault));
        router.syncOperator(1);
        router.syncOperator(2);
        assertEq(router.totalEffectiveWeight(), 0);

        token.mint(contributor, 1);
        vm.startPrank(contributor);
        token.approve(address(router), 1);
        vm.expectRevert(OperatorFeeRouter.ZeroEffectiveWeight.selector);
        router.addRewards(address(token), 1);
        vm.stopPrank();
    }

    function test_RewardAssetCapIsEnforced() public {
        for (uint160 i = 1; i < 64; ++i) {
            address asset = address(uint160(10_000 + i));
            vm.etch(asset, hex"00");
            _register(asset);
        }
        assertEq(router.rewardAssetCount(), 64);

        address extra = address(20_000);
        vm.etch(extra, hex"00");
        vm.prank(address(timelock));
        vm.expectRevert(OperatorFeeRouter.RewardAssetLimitReached.selector);
        router.registerRewardAsset(extra);
    }

    function test_DirectDonationCreatesNoEntitlementAndCanRecoverOnlySurplus() public {
        _add(token, 200 ether);
        token.mint(address(router), 50 ether);
        assertEq(router.pendingOperatorRewards(1, address(token)), 100 ether);
        assertEq(router.availableSurplus(address(token)), 50 ether);

        vm.prank(address(timelock));
        router.recoverSurplus(address(token), receiver, 50 ether);
        assertEq(token.balanceOf(receiver), 50 ether);
        assertEq(token.balanceOf(address(router)), 200 ether);

        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InsufficientSurplus.selector, address(token), 1, 0));
        router.recoverSurplus(address(token), receiver, 1);
    }

    function test_RecoveryRejectsZeroAmountAndInvalidReceivers() public {
        token.mint(address(router), 1 ether);

        vm.prank(address(timelock));
        vm.expectRevert(OperatorFeeRouter.ZeroAmount.selector);
        router.recoverSurplus(address(token), receiver, 0);

        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InvalidReceiver.selector, address(0)));
        router.recoverSurplus(address(token), address(0), 1);

        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InvalidReceiver.selector, address(router)));
        router.recoverSurplus(address(token), address(router), 1);
    }

    function test_NativeAssetIsRejected() public {
        vm.deal(address(this), 1);
        (bool success, bytes memory returndata) = address(router).call{value: 1}("");
        assertFalse(success);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(returndata), OperatorFeeRouter.NativeAssetUnsupported.selector);
    }

    function test_FeeOnTransferIngressRevertsAtomically() public {
        MockFeeToken feeToken = new MockFeeToken();
        _register(address(feeToken));
        feeToken.setFeeEnabled(true);
        feeToken.mint(contributor, 100 ether);

        vm.startPrank(contributor);
        feeToken.approve(address(router), 100 ether);
        vm.expectRevert();
        router.addRewards(address(feeToken), 100 ether);
        vm.stopPrank();

        assertEq(feeToken.balanceOf(contributor), 100 ether);
        assertEq(feeToken.balanceOf(address(router)), 0);
        assertEq(_liability(address(feeToken)), 0);
    }

    function test_SenderFeeIngressRevertsAtomically() public {
        MockSenderFeeToken feeToken = new MockSenderFeeToken();
        _register(address(feeToken));
        feeToken.setFeeEnabled(true);
        feeToken.mint(contributor, 110 ether);

        vm.startPrank(contributor);
        feeToken.approve(address(router), 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperatorFeeRouter.InexactTokenTransfer.selector, address(feeToken), 100 ether, 110 ether, 100 ether
            )
        );
        router.addRewards(address(feeToken), 100 ether);
        vm.stopPrank();

        assertEq(feeToken.balanceOf(contributor), 110 ether);
        assertEq(feeToken.balanceOf(address(router)), 0);
        assertEq(_liability(address(feeToken)), 0);
    }

    function test_FeeOnTransferClaimRevertsWithoutConsumingClaim() public {
        MockFeeToken feeToken = new MockFeeToken();
        _register(address(feeToken));
        _add(feeToken, 200 ether);
        feeToken.setFeeEnabled(true);

        vm.prank(alice);
        vm.expectRevert();
        router.claimOperatorRewards(1, address(feeToken), receiver);
        assertEq(router.pendingOperatorRewards(1, address(feeToken)), 100 ether);
        assertEq(_liability(address(feeToken)), 200 ether);
    }

    function test_ReentrantIngressIsBlockedWhileOuterContributionSucceeds() public {
        MockReentrantToken reentrant = new MockReentrantToken();
        _register(address(reentrant));
        reentrant.setCallback(
            address(router), abi.encodeCall(OperatorFeeRouter.addRewards, (address(reentrant), 1 ether))
        );
        _add(reentrant, 200 ether);

        assertTrue(reentrant.callbackAttempted());
        assertFalse(reentrant.callbackSucceeded());
        assertEq(_liability(address(reentrant)), 200 ether);
    }

    function test_ReentrantIngressCannotChangeWeightThroughSync() public {
        MockReentrantToken reentrant = new MockReentrantToken();
        _register(address(reentrant));
        registry.setMultiplier(1, 12_500);
        reentrant.setCallback(address(router), abi.encodeCall(OperatorFeeRouter.syncOperator, (1)));
        _add(reentrant, 200 ether);

        assertTrue(reentrant.callbackAttempted());
        assertFalse(reentrant.callbackSucceeded());
        assertEq(router.totalEffectiveWeight(), 20_000);
        assertEq(router.pendingOperatorRewards(1, address(reentrant)), 100 ether);
    }

    function test_ActivationIncreaseIsProspective() public {
        _add(token, 200 ether);
        registry.setMultiplier(1, 12_500);
        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Activation));
        assertEq(router.totalEffectiveWeight(), 22_500);

        _add(token, 225 ether);
        assertEq(router.pendingOperatorRewards(1, address(token)), 225 ether);
        assertEq(router.pendingOperatorRewards(2, address(token)), 200 ether);
    }

    function testFuzz_SyncClassifiesAndInstallsCanonicalState(
        uint16 rawPreviousMultiplier,
        uint16 rawCurrentMultiplier,
        bool ownerChanged
    ) public {
        uint16 previousMultiplier = uint16(bound(rawPreviousMultiplier, 10_000, 12_500));
        uint16 currentMultiplier = uint16(bound(rawCurrentMultiplier, 10_000, 12_500));

        registry.setMultiplier(1, previousMultiplier);
        router.syncOperator(1);
        uint256 totalWeightBefore = router.totalEffectiveWeight();
        if (ownerChanged) collection.setOwner(1, carol);
        registry.setMultiplier(1, currentMultiplier);

        OperatorFeeRouter.SyncKind expectedKind;
        if (!ownerChanged && currentMultiplier == previousMultiplier) {
            expectedKind = OperatorFeeRouter.SyncKind.Noop;
        } else if (!ownerChanged && currentMultiplier > previousMultiplier) {
            expectedKind = OperatorFeeRouter.SyncKind.Activation;
        } else {
            expectedKind = OperatorFeeRouter.SyncKind.Transfer;
        }

        assertEq(uint8(router.syncOperator(1)), uint8(expectedKind));
        (address installedOwner, uint16 installedMultiplier, uint16 installedWeight, bool initialized) =
            router.operatorState(1);
        assertTrue(initialized);
        assertEq(installedOwner, ownerChanged ? carol : alice);
        assertEq(installedMultiplier, currentMultiplier);
        assertEq(installedWeight, currentMultiplier);
        assertEq(router.totalEffectiveWeight(), totalWeightBefore - previousMultiplier + currentMultiplier);
    }

    function testFuzz_ActivationWeightAppliesOnlyProspectively(uint16 rawMultiplier) public {
        uint16 newMultiplier = uint16(bound(rawMultiplier, 10_001, 12_500));
        _add(token, 20_000);
        registry.setMultiplier(1, newMultiplier);
        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Activation));
        _add(token, uint256(newMultiplier) + 10_000);

        assertEq(router.pendingOperatorRewards(1, address(token)), 10_000 + uint256(newMultiplier));
        assertEq(router.pendingOperatorRewards(2, address(token)), 20_000);
    }

    function testFuzz_TransferRedistributionConservesScaledValue(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1e24);
        _add(token, amount);

        BookSnapshot memory beforeBook = _bookSnapshot(address(token));
        (,, uint16 oldWeight,) = router.operatorState(1);
        uint256 ray = router.RAY();
        uint256 scaledForfeiture = _scaledOperatorEntitlement(1, address(token), oldWeight, beforeBook.indexRay, ray);
        uint256 expectedForfeited = scaledForfeiture / ray;
        uint256 expectedForfeitedRemainder = scaledForfeiture % ray;
        uint256 redistributionDenominator = router.totalEffectiveWeight() - oldWeight;

        collection.setOwner(1, carol);
        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Transfer));

        BookSnapshot memory afterBook = _bookSnapshot(address(token));
        assertEq(afterBook.totalAdded, beforeBook.totalAdded);
        assertEq(afterBook.totalClaimed, beforeBook.totalClaimed);
        assertEq(afterBook.liability, beforeBook.liability);
        assertEq(afterBook.totalForfeited, expectedForfeited);
        assertEq(afterBook.totalForfeitedRemainder, expectedForfeitedRemainder);
        assertEq(
            (afterBook.indexRay - beforeBook.indexRay) * redistributionDenominator + afterBook.indexRemainder,
            expectedForfeited * ray + expectedForfeitedRemainder + beforeBook.indexRemainder
        );
        assertEq(router.pendingOperatorRewards(1, address(token)), 0);
    }

    function test_OwnershipChangeForfeitsAndRedistributesAllStaleRewards() public {
        _add(token, 200 ether);
        collection.setOwner(1, carol);
        registry.setMultiplier(1, 10_000);
        _add(token, 200 ether);

        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Transfer));
        assertEq(router.pendingOperatorRewards(1, address(token)), 0);
        assertEq(router.pendingOperatorRewards(2, address(token)), 400 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.NotOperatorOwner.selector, 1, alice, carol));
        router.claimOperatorRewards(1, address(token), alice);

        vm.prank(bob);
        assertEq(router.claimOperatorRewards(2, address(token), bob), 400 ether);
        assertEq(token.balanceOf(bob), 400 ether);
        assertEq(_liability(address(token)), 0);
    }

    function test_IndexCapacityQueuesForfeitureWithoutBlockingOtherAssets() public {
        MockERC20 other = new MockERC20("Other Reward", "OTHER");
        _register(address(other));
        registry.setMultiplier(2, 11_000);
        router.syncOperator(2);
        _add(token, 231 ether + 1);
        _add(other, 231 ether);

        (uint256 originalIndex, uint256 originalIndexRemainder,,,,,,,) = router.rewardBook(address(token));
        assertGt(originalIndexRemainder, 0);
        uint256 saturatedIndex = type(uint256).max;
        router.harnessSetRewardIndex(address(token), saturatedIndex);
        router.harnessSetOperatorCheckpoint(1, address(token), saturatedIndex - originalIndex);
        router.harnessSetOperatorCheckpoint(2, address(token), saturatedIndex - originalIndex);

        collection.setOwner(1, carol);
        router.syncOperator(1);

        (uint256 pendingAmount, uint256 pendingRemainder) = router.pendingForfeiture(1, address(token));
        assertGt(pendingAmount, 0);
        assertGt(pendingRemainder, 0);
        (, uint256 retainedIndexRemainder,,,,,,,) = router.rewardBook(address(token));
        assertEq(retainedIndexRemainder, originalIndexRemainder);
        assertEq(_liability(address(token)), 231 ether + 1);
        assertEq(router.syncedOwner(1), carol);
        assertEq(router.effectiveWeight(1), 10_000);
        assertEq(router.totalEffectiveWeight(), 21_000);

        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardIndexCapacityExceeded.selector, address(token)));
        router.flushPendingForfeiture(1, address(token));
        (uint256 retainedPendingAmount, uint256 retainedPendingRemainder) = router.pendingForfeiture(1, address(token));
        assertEq(retainedPendingAmount, pendingAmount);
        assertEq(retainedPendingRemainder, pendingRemainder);

        token.mint(contributor, 1);
        vm.startPrank(contributor);
        token.approve(address(router), 1);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardIndexCapacityExceeded.selector, address(token)));
        router.addRewards(address(token), 1);
        vm.stopPrank();
        assertEq(token.balanceOf(contributor), 1);

        assertEq(router.pendingOperatorRewards(1, address(other)), 0);
        assertEq(router.pendingOperatorRewards(2, address(other)), 231 ether);

        vm.prank(bob);
        assertEq(router.claimOperatorRewards(2, address(other), bob), 231 ether);
    }

    function test_NewOwnerBeginsOnlyAfterTransferSync() public {
        _add(token, 200 ether);
        collection.setOwner(1, carol);
        router.syncOperator(1);
        _add(token, 200 ether);

        assertEq(router.pendingOperatorRewards(1, address(token)), 100 ether);
        vm.prank(carol);
        assertEq(router.claimOperatorRewards(1, address(token), carol), 100 ether);
    }

    function test_CurrentOwnerEmptyClaimPersistsDetectedTransfer() public {
        _add(token, 200 ether);
        collection.setOwner(1, carol);

        vm.prank(carol);
        assertEq(router.claimOperatorRewards(1, address(token), carol), 0);

        (address owner,,, bool initialized) = router.operatorState(1);
        assertEq(owner, carol);
        assertTrue(initialized);
        assertEq(router.pendingOperatorRewards(2, address(token)), 200 ether);
    }

    function test_LowerMultiplierWithSameOwnerTriggersForfeiture() public {
        registry.setMultiplier(1, 12_500);
        router.syncOperator(1);
        _add(token, 225 ether);
        registry.setMultiplier(1, 10_000);

        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Transfer));
        assertEq(router.pendingOperatorRewards(1, address(token)), 0);
        assertEq(router.pendingOperatorRewards(2, address(token)), 225 ether);
    }

    function test_OwnerMismatchWinsEvenIfNewOwnerReactivates() public {
        registry.setMultiplier(1, 12_500);
        router.syncOperator(1);
        _add(token, 225 ether);
        collection.setOwner(1, carol);
        registry.setMultiplier(1, 12_000);

        router.syncOperator(1);
        (address owner, uint16 multiplier, uint16 weight,) = router.operatorState(1);
        assertEq(owner, carol);
        assertEq(multiplier, 12_000);
        assertEq(weight, 12_000);
        assertEq(router.pendingOperatorRewards(1, address(token)), 0);
        assertEq(router.pendingOperatorRewards(2, address(token)), 225 ether);
    }

    function test_IdenticalSnapshotRoundTripIsIntentionallyUnobservable() public {
        _add(token, 200 ether);
        collection.setOwner(1, carol);
        collection.setOwner(1, alice);
        registry.setMultiplier(1, 10_000);

        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Noop));
        assertEq(router.pendingOperatorRewards(1, address(token)), 100 ether);
    }

    function test_UserToVaultForfeitsThenInstallsZeroWeight() public {
        _add(token, 200 ether);
        collection.setOwner(1, address(vault));
        registry.setMultiplier(1, 10_000);
        router.syncOperator(1);

        (address owner,, uint16 weight,) = router.operatorState(1);
        assertEq(owner, address(vault));
        assertEq(weight, 0);
        assertEq(router.totalEffectiveWeight(), 10_000);
        assertEq(router.pendingOperatorRewards(2, address(token)), 200 ether);
    }

    function test_VaultToUserStartsAtSyncBoundary() public {
        collection.setOwner(1, address(vault));
        router.syncOperator(1);
        _add(token, 100 ether);
        assertEq(router.pendingOperatorRewards(2, address(token)), 100 ether);

        collection.setOwner(1, carol);
        router.syncOperator(1);
        assertEq(router.pendingOperatorRewards(1, address(token)), 0);
        _add(token, 200 ether);
        assertEq(router.pendingOperatorRewards(1, address(token)), 100 ether);
    }

    function test_ZeroOtherWeightQueuesForfeitureUntilAnotherOperatorIsEligible() public {
        collection.setOwner(2, address(vault));
        router.syncOperator(2);
        _add(token, 100 ether);

        collection.setOwner(1, carol);
        router.syncOperator(1);
        (uint256 pendingAmount, uint256 pendingRemainder) = router.pendingForfeiture(1, address(token));
        assertEq(pendingAmount, 100 ether);
        assertEq(pendingRemainder, 0);

        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.NoOtherEffectiveWeight.selector, 1));
        router.flushPendingForfeiture(1, address(token));

        collection.setOwner(2, bob);
        router.syncOperator(2);
        router.flushPendingForfeiture(1, address(token));
        assertEq(router.pendingOperatorRewards(1, address(token)), 0);
        assertEq(router.pendingOperatorRewards(2, address(token)), 100 ether);
    }

    function test_PendingForfeitureExcludesIdButPreservesItsNormalLaterAccrual() public {
        collection.setOwner(2, address(vault));
        router.syncOperator(2);
        _add(token, 100 ether);
        collection.setOwner(1, carol);
        router.syncOperator(1);

        _add(token, 25 ether);
        collection.setOwner(2, bob);
        router.syncOperator(2);
        router.flushPendingForfeiture(1, address(token));

        assertEq(router.pendingOperatorRewards(1, address(token)), 25 ether);
        assertEq(router.pendingOperatorRewards(2, address(token)), 100 ether);
    }

    function test_ClaimPaysCurrentOwnerToArbitraryReceiverAndCannotDoubleClaim() public {
        _add(token, 200 ether);
        vm.prank(alice);
        assertEq(router.claimOperatorRewards(1, address(token), receiver), 100 ether);
        assertEq(token.balanceOf(receiver), 100 ether);

        vm.prank(alice);
        vm.expectRevert(OperatorFeeRouter.NoRewards.selector);
        router.claimOperatorRewards(1, address(token), receiver);
    }

    function test_ClaimRejectsInvalidCallerReceiverVaultAndUninitializedOperator() public {
        _add(token, 200 ether);

        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InvalidReceiver.selector, address(0)));
        router.claimOperatorRewards(1, address(token), address(0));

        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.NotOperatorOwner.selector, 1, address(this), alice));
        router.claimOperatorRewards(1, address(token), receiver);

        collection.setOwner(1, address(vault));
        router.syncOperator(1);
        vm.prank(address(vault));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.VaultCannotClaim.selector, 1));
        router.claimOperatorRewards(1, address(token), receiver);

        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.OperatorNotInitialized.selector, 3));
        router.syncOperator(3);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.OperatorNotInitialized.selector, 3));
        router.pendingOperatorRewards(3, address(token));
    }

    function test_FlushRejectsWhenNothingIsPending() public {
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.NoPendingForfeiture.selector, 1, address(token)));
        router.flushPendingForfeiture(1, address(token));
    }

    function test_InvalidCanonicalMultiplierBlocksSync() public {
        registry.setMultiplier(1, 9_999);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InvalidMultiplier.selector, 9_999));
        router.syncOperator(1);

        registry.setMultiplier(1, 12_501);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.InvalidMultiplier.selector, 12_501));
        router.pendingOperatorRewards(1, address(token));
    }

    function test_OperationsOnOneAssetDoNotMutateAnotherAssetBook() public {
        MockERC20 other = new MockERC20("Other", "OTHER");
        _register(address(other));
        _add(token, 200 ether);
        _add(other, 600 ether);
        bytes32 otherBookBefore = _bookDigest(address(other));
        uint256 otherPendingBefore = router.pendingOperatorRewards(1, address(other));
        uint256 otherBalanceBefore = other.balanceOf(address(router));

        vm.prank(alice);
        router.claimOperatorRewards(1, address(token), alice);
        token.mint(address(router), 25 ether);
        vm.prank(address(timelock));
        router.recoverSurplus(address(token), receiver, 25 ether);
        vm.prank(address(timelock));
        router.setRewardAssetEnabled(address(token), false);

        assertEq(_bookDigest(address(other)), otherBookBefore);
        assertEq(router.pendingOperatorRewards(1, address(other)), otherPendingBefore);
        assertEq(other.balanceOf(address(router)), otherBalanceBefore);
    }

    function test_TinyRewardsCarrySettlementRemainder() public {
        _add(token, 1);
        assertEq(router.pendingOperatorRewards(1, address(token)), 0);
        _add(token, 1);
        assertEq(router.pendingOperatorRewards(1, address(token)), 1);
        assertEq(router.pendingOperatorRewards(2, address(token)), 1);
    }

    function testFuzz_ContributionConservesLiability(uint128 first, uint128 second) public {
        uint256 maxEach = router.MAX_OUTSTANDING_REWARD_UNITS() / 2;
        uint256 firstAmount = bound(uint256(first), 1, maxEach);
        uint256 secondAmount = bound(uint256(second), 1, maxEach);
        _add(token, firstAmount);
        _add(token, secondAmount);
        assertEq(_liability(address(token)), firstAmount + secondAmount);
        assertEq(token.balanceOf(address(router)), firstAmount + secondAmount);
        assertLe(
            router.pendingOperatorRewards(1, address(token)) + router.pendingOperatorRewards(2, address(token)),
            firstAmount + secondAmount
        );
    }

    function _register(address asset) internal {
        vm.prank(address(timelock));
        router.registerRewardAsset(asset);
    }

    function _add(MockERC20 rewardToken, uint256 amount) internal {
        rewardToken.mint(contributor, amount);
        vm.startPrank(contributor);
        rewardToken.approve(address(router), amount);
        router.addRewards(address(rewardToken), amount);
        vm.stopPrank();
    }

    function _liability(address asset) internal view returns (uint256 liability) {
        (,,,, liability,,,,) = router.rewardBook(asset);
    }

    function _bookDigest(address asset) internal view returns (bytes32 digest) {
        digest = keccak256(abi.encode(_bookSnapshot(asset)));
    }

    function _bookSnapshot(address asset) internal view returns (BookSnapshot memory book) {
        (bool success, bytes memory returndata) =
            address(router).staticcall(abi.encodeWithSignature("rewardBook(address)", asset));
        require(success, "reward book read failed");
        book = abi.decode(returndata, (BookSnapshot));
    }

    function _scaledOperatorEntitlement(uint256 operatorId, address asset, uint16 weight, uint256 indexRay, uint256 ray)
        internal
        view
        returns (uint256 scaled)
    {
        (uint256 checkpointRay, uint256 settlementRemainderRay, uint256 accrued) =
            router.operatorAssetState(operatorId, asset);
        scaled = accrued * ray + uint256(weight) * (indexRay - checkpointRay) + settlementRemainderRay;
    }
}
