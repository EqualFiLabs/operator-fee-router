// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {OperatorFeeRouterTimelock} from "../src/OperatorFeeRouterTimelock.sol";
import {OperatorFeeRouterHarness} from "./mocks/OperatorFeeRouterHarness.sol";
import {MockActivationRegistry, MockOperatorCollection, MockVault} from "./mocks/MockOperatorSystem.sol";
import {MockERC20, MockFeeToken, MockReentrantToken} from "./mocks/MockTokens.sol";

contract OperatorFeeRouterLifecycleTest is Test {
    address internal proposer = makeAddr("proposer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    MockVault internal vault;
    MockOperatorCollection internal collection;
    MockActivationRegistry internal registry;
    OperatorFeeRouterTimelock internal timelock;
    OperatorFeeRouterHarness internal router;
    MockERC20 internal token;

    function setUp() public {
        vault = new MockVault();
        collection = new MockOperatorCollection(address(vault));
        registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));
        collection.setOwner(1, alice);
        collection.setOwner(2, bob);
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new OperatorFeeRouterTimelock(proposers, executors);
        router = new OperatorFeeRouterHarness(address(collection), address(registry), address(vault), address(timelock));
        router.bootstrapOperators(2);
        router.harnessFinalizeBootstrap();
        token = new MockERC20("Lifecycle", "LIFE");
        _register(token);
    }

    function test_ProposerManagesAssetsImmediatelyButCannotExpireOrRecover() public {
        MockERC20 other = new MockERC20("Other", "OTHER");
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.Unauthorized.selector, alice));
        vm.prank(alice);
        router.registerRewardAsset(address(other));
        _register(other);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.Unauthorized.selector, alice));
        vm.prank(alice);
        router.setRewardAssetEnabled(address(other), false);
        _claimOnly(other);
        vm.startPrank(proposer);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.Unauthorized.selector, proposer));
        router.deregisterRewardAsset(address(other));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.Unauthorized.selector, proposer));
        router.recoverSurplus(address(other), proposer, 1);
        router.setRewardAssetEnabled(address(other), true);
        vm.stopPrank();
        assertTrue(router.rewardAssetEnabled(address(other)));
    }

    function test_ManagementAuthorityFollowsTimelockedProposerRotation() public {
        bytes32 role = timelock.PROPOSER_ROLE();
        _execute(address(timelock), abi.encodeCall(timelock.grantRole, (role, alice)), "grant");
        vm.prank(alice);
        router.setRewardAssetEnabled(address(token), false);
        _execute(address(timelock), abi.encodeCall(timelock.revokeRole, (role, proposer)), "revoke");
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), alice));
        assertFalse(timelock.hasRole(timelock.CANCELLER_ROLE(), proposer));

        bytes memory data = abi.encodeCall(router.deregisterRewardAsset, (address(token)));
        bytes32 salt = keccak256("post rotation");
        vm.prank(alice);
        timelock.schedule(address(router), 0, data, bytes32(0), salt, 24 hours);
        bytes32 id = timelock.hashOperation(address(router), 0, data, bytes32(0), salt);
        vm.expectRevert();
        vm.prank(proposer);
        timelock.cancel(id);
        vm.prank(alice);
        timelock.cancel(id);
        assertFalse(timelock.isOperation(id));

        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.Unauthorized.selector, proposer));
        vm.prank(proposer);
        router.setRewardAssetEnabled(address(token), true);
        vm.prank(alice);
        router.setRewardAssetEnabled(address(token), true);
        assertTrue(router.rewardAssetEnabled(address(token)));
    }

    function test_ClaimOnlyPreservesSettlementTransfersClaimsAndReenablement() public {
        _add(token, 100 ether);
        _claimOnly(token);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetDisabled.selector, address(token)));
        router.addRewards(address(token), 1);
        registry.setMultiplier(1, 12_500);
        router.syncOperator(1);
        assertEq(router.pendingOperatorRewards(1, address(token)), 50 ether);
        collection.setOwner(2, carol);
        router.syncOperator(2);
        assertEq(router.pendingOperatorRewards(1, address(token)), 100 ether);
        vm.prank(alice);
        assertEq(router.claimOperatorRewards(1, address(token), alice), 100 ether);
        assertTrue(router.isRewardAsset(address(token)));
        vm.prank(proposer);
        router.setRewardAssetEnabled(address(token), true);
        _add(token, 9 ether);
        assertEq(router.pendingOperatorRewards(1, address(token)), 5 ether);
    }

    function test_DeregistrationDelayCancellationAndExecutionCutoff() public {
        _add(token, 100 ether);
        _claimOnly(token);
        bytes memory data = abi.encodeCall(router.deregisterRewardAsset, (address(token)));
        bytes32 salt = keccak256("retire");
        _schedule(address(router), data, salt);
        vm.expectRevert();
        timelock.execute(address(router), 0, data, bytes32(0), salt);
        bytes32 operation = timelock.hashOperation(address(router), 0, data, bytes32(0), salt);
        vm.prank(proposer);
        timelock.cancel(operation);
        vm.warp(block.timestamp + 24 hours);
        vm.expectRevert();
        timelock.execute(address(router), 0, data, bytes32(0), salt);
        assertEq(router.pendingOperatorRewards(1, address(token)), 50 ether);
        _schedule(address(router), data, salt);
        vm.warp(block.timestamp + 24 hours + 7 days);
        // Readiness does not expire claims: execution is the cutoff.
        vm.prank(alice);
        assertEq(router.claimOperatorRewards(1, address(token), alice), 50 ether);
        vm.expectEmit(true, false, false, true, address(router));
        emit OperatorFeeRouter.RewardAssetDeregistered(address(token), 50 ether);
        timelock.execute(address(router), 0, data, bytes32(0), salt);
        assertEq(router.expiredRewards(address(token)), 50 ether);
        assertEq(_liability(token), 0);
        assertEq(router.availableSurplus(address(token)), 50 ether);
        _assertRetired(token);
        _execute(
            address(router), abi.encodeCall(router.recoverSurplus, (address(token), proposer, 50 ether)), "recover"
        );
        assertEq(token.balanceOf(proposer), 50 ether);
        assertEq(router.expiredRewards(address(token)), 50 ether);
    }

    function test_DeregistrationRequiresClaimOnlyAndDoesNotDisableAnActiveAsset() public {
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotClaimOnly.selector, address(token)));
        vm.prank(address(timelock));
        router.deregisterRewardAsset(address(token));
        assertTrue(router.rewardAssetEnabled(address(token)));
        _claimOnly(token);
        _retire(token);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotRegistered.selector, address(token)));
        vm.prank(address(timelock));
        router.deregisterRewardAsset(address(token));
    }

    function test_ExpiryIncludesQueuedForfeitureDustAndPreservesOtherAssets() public {
        MockERC20 other = new MockERC20("Other", "OTHER");
        _register(other);
        registry.setMultiplier(2, 11_000);
        router.syncOperator(2);
        _add(token, 101);
        _add(other, 101);
        _claimOnly(token);
        collection.setOwner(2, address(vault));
        router.syncOperator(2);
        collection.setOwner(1, address(vault));
        router.syncOperator(1);
        (uint256 pending, uint256 fraction) = router.pendingForfeiture(1, address(token));
        assertGt(pending, 0);
        bytes32 otherBefore = _bookHash(other);
        token.mint(address(router), 7);
        _retire(token);
        assertEq(_bookHash(other), otherBefore);
        assertEq(router.expiredRewards(address(token)), 101);
        assertEq(router.availableSurplus(address(token)), 108);
        (uint256 storedPending, uint256 storedFraction) = router.pendingForfeiture(1, address(token));
        assertEq(storedPending, pending);
        assertEq(storedFraction, fraction);
        collection.setOwner(2, bob);
        router.syncOperator(2);
        router.flushPendingForfeiture(1, address(other));
        assertGt(router.pendingOperatorRewards(2, address(other)), 0);
        _assertRetired(token);
    }

    function test_ExpiryIncludesUnsettledFractionalDust() public {
        registry.setMultiplier(2, 11_000);
        router.syncOperator(2);
        _add(token, 101);
        registry.setMultiplier(1, 12_500);
        router.syncOperator(1);
        (, uint256 remainder, uint256 accrued) = router.operatorAssetState(1, address(token));
        (, uint256 globalRemainder,,,,,,,) = router.rewardBook(address(token));
        assertGt(remainder, 0);
        assertGt(globalRemainder, 0);
        _claimOnly(token);
        _retire(token);
        assertEq(router.expiredRewards(address(token)), 101);
        assertEq(_liability(token), 0);
        (, uint256 historicalRemainder, uint256 historicalAccrued) = router.operatorAssetState(1, address(token));
        assertEq(historicalRemainder, remainder);
        assertEq(historicalAccrued, accrued);
        _assertRetired(token);
    }

    function test_ClaimOnlyPendingForfeitureCanBeFlushed() public {
        collection.setOwner(2, address(vault));
        router.syncOperator(2);
        _add(token, 99);
        _claimOnly(token);
        collection.setOwner(1, carol);
        router.syncOperator(1);
        collection.setOwner(2, bob);
        router.syncOperator(2);
        router.flushPendingForfeiture(1, address(token));
        vm.prank(bob);
        assertEq(router.claimOperatorRewards(2, address(token), bob), 99);
    }

    function test_ExpiryDoesNotCallTokenAndAllowsZeroLiability() public {
        _claimOnly(token);
        vm.mockCallRevert(address(token), abi.encodeWithSelector(token.balanceOf.selector), "unavailable");
        _retire(token);
        assertEq(router.expiredRewards(address(token)), 0);
        _assertRetired(token);
    }

    function testFuzz_RemovalAndCapacityReuse(uint8 rawIndex) public {
        MockERC20[64] memory assets;
        assets[0] = token;
        for (uint256 i = 1; i < 64; ++i) {
            assets[i] = new MockERC20("Slot", "SLOT");
            _register(assets[i]);
        }
        uint256 index = bound(uint256(rawIndex), 0, 63);
        MockERC20 replacement = new MockERC20("Replacement", "NEW");
        vm.expectRevert(OperatorFeeRouter.RewardAssetLimitReached.selector);
        vm.prank(proposer);
        router.registerRewardAsset(address(replacement));
        _claimOnly(assets[index]);
        _retire(assets[index]);
        assertEq(router.rewardAssetCount(), 63);
        for (uint256 i; i < 63; ++i) {
            assertEq(router.rewardAssetAt(i), address(assets[i == index ? 63 : i]));
        }
        _register(replacement);
        assertEq(router.rewardAssetAt(63), address(replacement));
        assertEq(router.rewardAssetCount(), 64);
        _assertRetired(assets[index]);
    }

    function test_FailedRecoveryRollsBackAndDoesNotReviveExpiredRewards() public {
        MockFeeToken fee = new MockFeeToken();
        _register(fee);
        _add(fee, 100);
        _claimOnly(fee);
        _retire(fee);
        fee.setFeeEnabled(true);
        vm.expectRevert(
            abi.encodeWithSelector(OperatorFeeRouter.InexactTokenTransfer.selector, address(fee), 100, 100, 90)
        );
        vm.prank(address(timelock));
        router.recoverSurplus(address(fee), proposer, 100);
        assertEq(fee.balanceOf(address(router)), 100);
        assertEq(fee.balanceOf(proposer), 0);
        assertEq(router.expiredRewards(address(fee)), 100);
        assertEq(_liability(fee), 0);
        fee.setFeeEnabled(false);
        _execute(address(router), abi.encodeCall(router.recoverSurplus, (address(fee), proposer, 100)), "retry");
        assertEq(fee.balanceOf(proposer), 100);
    }

    function test_ReadyDeregistrationCannotExecuteInsideTokenCallback() public {
        _add(token, 100);
        _claimOnly(token);
        bytes memory data = abi.encodeCall(router.deregisterRewardAsset, (address(token)));
        bytes32 salt = keccak256("callback");
        _schedule(address(router), data, salt);
        vm.warp(block.timestamp + 24 hours);
        MockReentrantToken callbackToken = new MockReentrantToken();
        _register(callbackToken);
        callbackToken.setCallback(
            address(timelock), abi.encodeCall(timelock.execute, (address(router), 0, data, bytes32(0), salt))
        );
        _add(callbackToken, 100);
        assertTrue(callbackToken.callbackAttempted());
        assertFalse(callbackToken.callbackSucceeded());
        assertTrue(router.isRewardAsset(address(token)));
        timelock.execute(address(router), 0, data, bytes32(0), salt);
        assertTrue(router.isRewardAssetDeregistered(address(token)));
    }

    function test_BatchedRecoveryFailureRollsBackDeregistration() public {
        MockFeeToken fee = new MockFeeToken();
        _register(fee);
        _add(fee, 100);
        _claimOnly(fee);
        address[] memory targets = new address[](2);
        targets[0] = address(router);
        targets[1] = address(router);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(router.deregisterRewardAsset, (address(fee)));
        calls[1] = abi.encodeCall(router.recoverSurplus, (address(fee), proposer, 100));
        bytes32 salt = keccak256("expiry-and-recovery");
        vm.prank(proposer);
        timelock.scheduleBatch(targets, values, calls, bytes32(0), salt, 24 hours);
        vm.warp(block.timestamp + 24 hours);
        fee.setFeeEnabled(true);
        vm.expectRevert();
        timelock.executeBatch(targets, values, calls, bytes32(0), salt);
        assertTrue(router.isRewardAsset(address(fee)));
        assertFalse(router.isRewardAssetDeregistered(address(fee)));
        assertEq(router.expiredRewards(address(fee)), 0);
        assertEq(_liability(fee), 100);
        assertEq(router.rewardAssetCount(), 2);
        fee.setFeeEnabled(false);
        timelock.executeBatch(targets, values, calls, bytes32(0), salt);
        assertEq(router.expiredRewards(address(fee)), 100);
        assertEq(router.rewardAssetCount(), 1);
        assertEq(fee.balanceOf(proposer), 100);
    }

    function _assertRetired(MockERC20 asset) internal {
        address a = address(asset);
        assertTrue(router.isRewardAssetDeregistered(a));
        assertFalse(router.isRewardAsset(a));
        assertFalse(router.rewardAssetEnabled(a));
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetPermanentlyDeregistered.selector, a));
        vm.prank(proposer);
        router.registerRewardAsset(a);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotRegistered.selector, a));
        vm.prank(proposer);
        router.setRewardAssetEnabled(a, true);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotRegistered.selector, a));
        router.addRewards(a, 1);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotRegistered.selector, a));
        vm.prank(alice);
        router.claimOperatorRewards(1, a, alice);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotRegistered.selector, a));
        router.pendingOperatorRewards(1, a);
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.RewardAssetNotRegistered.selector, a));
        router.flushPendingForfeiture(1, a);
    }

    function _register(MockERC20 asset) internal {
        vm.prank(proposer);
        router.registerRewardAsset(address(asset));
    }

    function _claimOnly(MockERC20 asset) internal {
        vm.prank(proposer);
        router.setRewardAssetEnabled(address(asset), false);
    }

    function _retire(MockERC20 asset) internal {
        _execute(
            address(router),
            abi.encodeCall(router.deregisterRewardAsset, (address(asset))),
            keccak256(abi.encode(asset))
        );
    }

    function _add(MockERC20 asset, uint256 amount) internal {
        asset.mint(address(this), amount);
        asset.approve(address(router), amount);
        router.addRewards(address(asset), amount);
    }

    function _liability(MockERC20 asset) internal view returns (uint256 amount) {
        (,,,, amount,,,,) = router.rewardBook(address(asset));
    }

    function _bookHash(MockERC20 asset) internal view returns (bytes32) {
        (bool ok, bytes memory result) =
            address(router).staticcall(abi.encodeWithSignature("rewardBook(address)", address(asset)));
        assertTrue(ok);
        return keccak256(result);
    }

    function _schedule(address target, bytes memory data, bytes32 salt) internal {
        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, 24 hours);
    }

    function _execute(address target, bytes memory data, bytes32 salt) internal {
        _schedule(target, data, salt);
        vm.warp(block.timestamp + 24 hours);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }
}
