// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {OperatorFeeRouter} from "../../src/OperatorFeeRouter.sol";
import {OperatorFeeRouterTimelock} from "../../src/OperatorFeeRouterTimelock.sol";
import {MockActivationRegistry, MockOperatorCollection, MockVault} from "../mocks/MockOperatorSystem.sol";

contract RouterLifecycleHarness is OperatorFeeRouter {
    constructor(address collection, address registry, address vault, address timelock)
        OperatorFeeRouter(collection, registry, vault, timelock)
    {}

    /// @dev Models a completed two-operator bootstrap for bounded lifecycle proofs.
    function harnessFinalizeBoundedBootstrap() external {
        nextOperatorId = LAST_OPERATOR_ID + 1;
        bootstrapFinalized = true;
    }

    /// @dev Models a valid prior bootstrap prefix whose weight is supplied explicitly.
    function harnessSeedBootstrap(uint256 cursor, uint256 priorWeight) external {
        require(cursor >= FIRST_OPERATOR_ID && cursor <= LAST_OPERATOR_ID, "cursor");
        require(!bootstrapFinalized, "finalized");
        nextOperatorId = cursor;
        totalEffectiveWeight = priorWeight;
    }
}

contract RouterLifecycleTimelockHarness is OperatorFeeRouterTimelock {
    constructor(address proposer, address executor)
        OperatorFeeRouterTimelock(_singleton(proposer), _singleton(executor))
    {}

    /// @dev Test-only helper that isolates the router's sender boundary; it does not model scheduling or elapsed time.
    function callAsTimelock(address target, bytes calldata data) external returns (bool success, bytes memory result) {
        (success, result) = target.call(data);
    }

    function _singleton(address account) private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }
}

contract FormalBoundaryToken {
    uint8 private _decimals;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function mint(address receiver, uint256 amount) external {
        balanceOf[receiver] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address receiver, uint256 amount) external returns (bool) {
        _transfer(msg.sender, receiver, amount);
        return true;
    }

    function transferFrom(address sender, address receiver, uint256 amount) external returns (bool) {
        uint256 approved = allowance[sender][msg.sender];
        require(approved >= amount, "allowance");
        allowance[sender][msg.sender] = approved - amount;
        _transfer(sender, receiver, amount);
        return true;
    }

    function _transfer(address sender, address receiver, uint256 amount) private {
        uint256 balance = balanceOf[sender];
        require(balance >= amount, "balance");
        balanceOf[sender] = balance - amount;
        balanceOf[receiver] += amount;
    }
}

contract FormalRawDecimalsFallback {
    uint256 private _rawDecimals;

    constructor(uint256 rawDecimals_) {
        _rawDecimals = rawDecimals_;
    }

    fallback() external {
        uint256 value = _rawDecimals;
        assembly ("memory-safe") {
            mstore(0, value)
            return(0, 32)
        }
    }
}

contract FormalEmptyDecimalsFallback {
    fallback() external {}
}

contract FormalRevertingDecimalsFallback {
    fallback() external {
        revert();
    }
}

contract RouterLifecycleHalmosTest is Test {
    address internal constant PROPOSER = address(0x1111);
    address internal constant OUTSIDER = address(0x2222);
    address internal constant ALICE = address(0x3333);
    address internal constant BOB = address(0x4444);
    address internal constant RECEIVER = address(0x5555);
    address internal constant EXECUTOR = address(0x6666);

    MockVault internal vault;
    MockOperatorCollection internal collection;
    MockActivationRegistry internal registry;
    RouterLifecycleTimelockHarness internal timelock;
    RouterLifecycleHarness internal router;

    function check_outsiderCannotManageExpireOrRecover() public {
        _deployLifecycleSystem();
        FormalBoundaryToken token = new FormalBoundaryToken(18);
        FormalBoundaryToken other = new FormalBoundaryToken(18);
        _register(token);
        _setEnabled(token, false);
        token.mint(address(router), 1);

        assertFalse(_callAs(OUTSIDER, address(router), abi.encodeCall(router.registerRewardAsset, (address(other)))));
        assertFalse(
            _callAs(OUTSIDER, address(router), abi.encodeCall(router.setRewardAssetEnabled, (address(token), true)))
        );
        assertFalse(_callAs(OUTSIDER, address(router), abi.encodeCall(router.deregisterRewardAsset, (address(token)))));
        assertFalse(
            _callAs(OUTSIDER, address(router), abi.encodeCall(router.recoverSurplus, (address(token), RECEIVER, 1)))
        );

        assertEq(router.rewardAssetCount(), 1);
        assertTrue(router.isRewardAsset(address(token)));
        assertFalse(router.rewardAssetEnabled(address(token)));
        assertEq(token.balanceOf(RECEIVER), 0);
    }

    function check_proposerCanManageButCannotExpireOrRecover() public {
        _deployLifecycleSystem();
        FormalBoundaryToken token = new FormalBoundaryToken(18);
        _register(token);
        _setEnabled(token, false);
        token.mint(address(router), 1);

        assertFalse(_callAs(PROPOSER, address(router), abi.encodeCall(router.deregisterRewardAsset, (address(token)))));
        assertFalse(
            _callAs(PROPOSER, address(router), abi.encodeCall(router.recoverSurplus, (address(token), RECEIVER, 1)))
        );

        _setEnabled(token, true);
        assertTrue(router.rewardAssetEnabled(address(token)));
        assertEq(token.balanceOf(RECEIVER), 0);
    }

    function check_timelockCanExpireAndRecoverNonzeroRewards() public {
        _deployLifecycleSystem();
        FormalBoundaryToken token = new FormalBoundaryToken(18);
        _register(token);
        _add(token, 100);
        _setEnabled(token, false);

        assertTrue(_callAsTimelock(abi.encodeCall(router.deregisterRewardAsset, (address(token)))));
        assertEq(router.expiredRewards(address(token)), 100);
        assertEq(_liability(token), 0);
        assertEq(router.availableSurplus(address(token)), 100);

        assertTrue(_callAsTimelock(abi.encodeCall(router.recoverSurplus, (address(token), RECEIVER, 100))));
        assertEq(token.balanceOf(RECEIVER), 100);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function check_timelockCannotExpireDepositEnabledAsset() public {
        _deployLifecycleSystem();
        FormalBoundaryToken token = new FormalBoundaryToken(18);
        _register(token);

        assertFalse(_callAsTimelock(abi.encodeCall(router.deregisterRewardAsset, (address(token)))));
        assertTrue(router.isRewardAsset(address(token)));
        assertTrue(router.rewardAssetEnabled(address(token)));
        assertEq(router.rewardAssetCount(), 1);
    }

    function check_scheduledExpiryRejectsEarlyExecutionAndExecutesWhenReady() public {
        _deployLifecycleSystem();
        FormalBoundaryToken token = new FormalBoundaryToken(18);
        _register(token);
        _add(token, 100);
        _setEnabled(token, false);

        bytes memory data = abi.encodeCall(router.deregisterRewardAsset, (address(token)));
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("formal-expiry");
        uint256 delay = timelock.getMinDelay();
        bytes32 operationId = timelock.hashOperation(address(router), 0, data, predecessor, salt);

        vm.prank(PROPOSER);
        timelock.schedule(address(router), 0, data, predecessor, salt, delay);
        assertTrue(timelock.isOperationPending(operationId));
        assertFalse(timelock.isOperationReady(operationId));

        assertFalse(
            _callAs(
                EXECUTOR,
                address(timelock),
                abi.encodeCall(timelock.execute, (address(router), 0, data, predecessor, salt))
            )
        );
        assertTrue(router.isRewardAsset(address(token)));
        assertEq(_liability(token), 100);

        vm.warp(block.timestamp + delay);
        assertTrue(timelock.isOperationReady(operationId));
        vm.prank(EXECUTOR);
        timelock.execute(address(router), 0, data, predecessor, salt);

        assertTrue(timelock.isOperationDone(operationId));
        assertFalse(router.isRewardAsset(address(token)));
        assertTrue(router.isRewardAssetDeregistered(address(token)));
        assertEq(router.expiredRewards(address(token)), 100);
        assertEq(_liability(token), 0);
        assertEq(token.balanceOf(address(router)), 100);
    }

    function check_claimOnlyRejectsDepositsButAllowsClaimsAndReenablement() public {
        _deployLifecycleSystem();
        FormalBoundaryToken token = new FormalBoundaryToken(18);
        _register(token);
        _add(token, 100);
        _setEnabled(token, false);

        token.mint(address(this), 1);
        token.approve(address(router), 1);
        (bool depositSucceeded,) = address(router).call(abi.encodeCall(router.addRewards, (address(token), 1)));
        assertFalse(depositSucceeded);
        assertEq(_liability(token), 100);

        vm.prank(ALICE);
        uint256 claimed = router.claimOperatorRewards(1, address(token), ALICE);
        assertEq(claimed, 50);
        assertEq(token.balanceOf(ALICE), 50);
        assertEq(_liability(token), 50);

        _setEnabled(token, true);
        _add(token, 20);
        assertTrue(router.rewardAssetEnabled(address(token)));
        assertEq(_liability(token), 70);
    }

    function check_permanentDeregistrationRejectsRegistrationAndEveryClaimPath() public {
        _deployLifecycleSystem();
        FormalBoundaryToken token = new FormalBoundaryToken(18);
        _register(token);
        _add(token, 100);
        _setEnabled(token, false);
        assertTrue(_callAsTimelock(abi.encodeCall(router.deregisterRewardAsset, (address(token)))));

        assertFalse(_callAs(PROPOSER, address(router), abi.encodeCall(router.registerRewardAsset, (address(token)))));
        assertFalse(
            _callAs(PROPOSER, address(router), abi.encodeCall(router.setRewardAssetEnabled, (address(token), true)))
        );
        assertFalse(_call(address(router), abi.encodeCall(router.addRewards, (address(token), 1))));
        assertFalse(
            _callAs(ALICE, address(router), abi.encodeCall(router.claimOperatorRewards, (1, address(token), ALICE)))
        );
        assertFalse(_call(address(router), abi.encodeCall(router.pendingOperatorRewards, (1, address(token)))));
        assertFalse(_call(address(router), abi.encodeCall(router.flushPendingForfeiture, (1, address(token)))));

        assertEq(router.rewardAssetCount(), 0);
        assertFalse(router.isRewardAsset(address(token)));
        assertTrue(router.isRewardAssetDeregistered(address(token)));
        assertEq(router.expiredRewards(address(token)), 100);
        assertEq(token.balanceOf(address(router)), 100);
    }

    function check_twoAssetRemovalPreservesTheSurvivor() public {
        _deployLifecycleSystem();
        FormalBoundaryToken first = new FormalBoundaryToken(18);
        FormalBoundaryToken second = new FormalBoundaryToken(18);
        _register(first);
        _register(second);
        _setEnabled(first, false);

        assertTrue(_callAsTimelock(abi.encodeCall(router.deregisterRewardAsset, (address(first)))));
        assertEq(router.rewardAssetCount(), 1);
        assertEq(router.rewardAssetAt(0), address(second));
        assertFalse(router.isRewardAsset(address(first)));
        assertTrue(router.isRewardAssetDeregistered(address(first)));
        assertTrue(router.isRewardAsset(address(second)));
        assertTrue(router.rewardAssetEnabled(address(second)));
    }

    function check_threeAssetRemovalPreservesBothSurvivors() public {
        _deployLifecycleSystem();
        FormalBoundaryToken first = new FormalBoundaryToken(18);
        FormalBoundaryToken second = new FormalBoundaryToken(18);
        FormalBoundaryToken third = new FormalBoundaryToken(18);
        _register(first);
        _register(second);
        _register(third);
        _setEnabled(second, false);

        assertTrue(_callAsTimelock(abi.encodeCall(router.deregisterRewardAsset, (address(second)))));
        assertEq(router.rewardAssetCount(), 2);
        assertEq(router.rewardAssetAt(0), address(first));
        assertEq(router.rewardAssetAt(1), address(third));
        assertTrue(router.isRewardAsset(address(first)));
        assertTrue(router.isRewardAsset(address(third)));
        assertFalse(router.isRewardAsset(address(second)));
        assertTrue(router.isRewardAssetDeregistered(address(second)));
    }

    function check_symbolicDecimalsAtMost18Register(uint8 rawDecimals) public {
        _deployBootstrapSystem();
        vm.assume(rawDecimals <= 18);
        uint8 decimals = rawDecimals;
        FormalBoundaryToken token = new FormalBoundaryToken(decimals);

        assertTrue(_callAs(PROPOSER, address(router), abi.encodeCall(router.registerRewardAsset, (address(token)))));
        assertTrue(router.isRewardAsset(address(token)));
        assertTrue(router.rewardAssetEnabled(address(token)));
        assertEq(router.rewardAssetCount(), 1);
    }

    function check_symbolicDecimalsAbove18Reject(uint8 rawDecimals) public {
        _deployBootstrapSystem();
        vm.assume(rawDecimals >= 19);
        uint8 decimals = rawDecimals;
        FormalBoundaryToken token = new FormalBoundaryToken(decimals);

        assertFalse(_callAs(PROPOSER, address(router), abi.encodeCall(router.registerRewardAsset, (address(token)))));
        assertFalse(router.isRewardAsset(address(token)));
        assertEq(router.rewardAssetCount(), 0);
    }

    function check_malformedRawDecimalsReject(uint16 rawDecimals) public {
        _deployBootstrapSystem();
        vm.assume(rawDecimals >= 256);
        uint256 malformed = uint256(rawDecimals);
        FormalRawDecimalsFallback token = new FormalRawDecimalsFallback(malformed);

        assertFalse(_callAs(PROPOSER, address(router), abi.encodeCall(router.registerRewardAsset, (address(token)))));
        assertFalse(router.isRewardAsset(address(token)));
        assertEq(router.rewardAssetCount(), 0);
    }

    function check_emptyDecimalsMetadataRejects() public {
        _deployBootstrapSystem();
        FormalEmptyDecimalsFallback token = new FormalEmptyDecimalsFallback();

        assertFalse(_callAs(PROPOSER, address(router), abi.encodeCall(router.registerRewardAsset, (address(token)))));
        assertFalse(router.isRewardAsset(address(token)));
        assertEq(router.rewardAssetCount(), 0);
    }

    function check_revertingDecimalsMetadataRejects() public {
        _deployBootstrapSystem();
        FormalRevertingDecimalsFallback token = new FormalRevertingDecimalsFallback();

        assertFalse(_callAs(PROPOSER, address(router), abi.encodeCall(router.registerRewardAsset, (address(token)))));
        assertFalse(router.isRewardAsset(address(token)));
        assertEq(router.rewardAssetCount(), 0);
    }

    function check_invalidOperatorIdsRejectSyncClaimAndFlush() public {
        _deployLifecycleSystem();
        FormalBoundaryToken token = new FormalBoundaryToken(18);
        _register(token);

        uint256 firstInvalid = 0;
        uint256 afterCollection = router.LAST_OPERATOR_ID() + 1;
        assertFalse(_call(address(router), abi.encodeCall(router.syncOperator, (firstInvalid))));
        assertFalse(
            _callAs(
                ALICE,
                address(router),
                abi.encodeCall(router.claimOperatorRewards, (firstInvalid, address(token), ALICE))
            )
        );
        assertFalse(
            _call(address(router), abi.encodeCall(router.flushPendingForfeiture, (firstInvalid, address(token))))
        );
        assertFalse(_call(address(router), abi.encodeCall(router.syncOperator, (afterCollection))));
        assertFalse(
            _callAs(
                ALICE,
                address(router),
                abi.encodeCall(router.claimOperatorRewards, (afterCollection, address(token), ALICE))
            )
        );
        assertFalse(
            _call(address(router), abi.encodeCall(router.flushPendingForfeiture, (afterCollection, address(token))))
        );
    }

    function check_bootstrapOneNonvaultOperatorUsesSymbolicMultiplier(
        uint16 rawOperatorId,
        uint16 rawMultiplier,
        uint32 priorWeight
    ) public {
        _deployBootstrapSystem();
        vm.assume(rawOperatorId >= 1 && rawOperatorId <= router.LAST_OPERATOR_ID());
        vm.assume(rawMultiplier >= router.MIN_MULTIPLIER_BPS() && rawMultiplier <= router.MAX_MULTIPLIER_BPS());
        uint256 operatorId = uint256(rawOperatorId);
        uint16 multiplier = rawMultiplier;
        vm.assume(uint256(priorWeight) <= (operatorId - 1) * router.MAX_MULTIPLIER_BPS());
        collection.setOwner(operatorId, ALICE);
        registry.setMultiplier(operatorId, multiplier);
        router.harnessSeedBootstrap(operatorId, uint256(priorWeight));

        (uint256 initializedCount, uint256 nextId) = router.bootstrapOperators(1);
        (address owner, uint16 syncedMultiplier, uint16 weight, bool initialized) = router.operatorState(operatorId);

        assertEq(initializedCount, 1);
        assertEq(nextId, operatorId + 1);
        assertEq(owner, ALICE);
        assertEq(syncedMultiplier, multiplier);
        assertEq(weight, multiplier);
        assertTrue(initialized);
        assertEq(router.totalEffectiveWeight(), uint256(priorWeight) + multiplier);
    }

    function check_finalizeRejectsIncompleteBootstrap() public {
        _deployBootstrapSystem();

        assertFalse(_call(address(router), abi.encodeCall(router.finalizeBootstrap, ())));
        assertFalse(router.bootstrapFinalized());
        assertEq(router.nextOperatorId(), router.FIRST_OPERATOR_ID());
    }

    function check_finalizeAfterFinalBatchAndRejectDuplicate(uint16 rawMultiplier, uint32 priorWeight) public {
        _deployBootstrapSystem();
        uint256 finalOperatorId = router.LAST_OPERATOR_ID();
        vm.assume(rawMultiplier >= router.MIN_MULTIPLIER_BPS() && rawMultiplier <= router.MAX_MULTIPLIER_BPS());
        uint16 multiplier = rawMultiplier;
        vm.assume(uint256(priorWeight) <= (finalOperatorId - 1) * router.MAX_MULTIPLIER_BPS());
        collection.setOwner(finalOperatorId, ALICE);
        registry.setMultiplier(finalOperatorId, multiplier);
        router.harnessSeedBootstrap(finalOperatorId, uint256(priorWeight));

        (uint256 initializedCount, uint256 nextId) = router.bootstrapOperators(router.MAX_BOOTSTRAP_BATCH());
        assertEq(initializedCount, 1);
        assertEq(nextId, finalOperatorId + 1);
        _assertInitialized(finalOperatorId);
        assertEq(router.totalEffectiveWeight(), uint256(priorWeight) + multiplier);

        router.finalizeBootstrap();
        assertTrue(router.bootstrapFinalized());
        assertEq(router.nextOperatorId(), router.LAST_OPERATOR_ID() + 1);
        assertEq(router.totalEffectiveWeight(), uint256(priorWeight) + multiplier);
        assertFalse(_call(address(router), abi.encodeCall(router.finalizeBootstrap, ())));
        assertFalse(_call(address(router), abi.encodeCall(router.bootstrapOperators, (1))));
        assertTrue(router.bootstrapFinalized());
    }

    function check_invalidMultiplierBootstrapRollsBack(
        uint16 rawOperatorId,
        uint16 rawMultiplier,
        uint32 priorWeight,
        bool aboveMaximum
    ) public {
        _deployBootstrapSystem();
        vm.assume(rawOperatorId >= 1 && rawOperatorId <= router.LAST_OPERATOR_ID());
        if (aboveMaximum) {
            vm.assume(rawMultiplier > router.MAX_MULTIPLIER_BPS());
        } else {
            vm.assume(rawMultiplier > 0 && rawMultiplier < router.MIN_MULTIPLIER_BPS());
        }
        uint256 operatorId = uint256(rawOperatorId);
        uint16 invalidMultiplier = rawMultiplier;
        vm.assume(uint256(priorWeight) <= (operatorId - 1) * router.MAX_MULTIPLIER_BPS());
        collection.setOwner(operatorId, ALICE);
        registry.setMultiplier(operatorId, invalidMultiplier);
        router.harnessSeedBootstrap(operatorId, uint256(priorWeight));

        assertFalse(_call(address(router), abi.encodeCall(router.bootstrapOperators, (1))));
        assertEq(router.nextOperatorId(), operatorId);
        assertEq(router.totalEffectiveWeight(), uint256(priorWeight));
        _assertUninitialized(operatorId);
        assertFalse(router.bootstrapFinalized());
    }

    function check_bootstrapProgressesFromSymbolicCursor(uint16 rawCursor, uint8 rawCount, uint32 priorWeight) public {
        _deployBootstrapSystem();
        vm.assume(rawCursor >= 1 && rawCursor <= router.LAST_OPERATOR_ID() - 2);
        vm.assume(rawCount >= 1 && rawCount <= 3);
        uint256 cursor = uint256(rawCursor);
        uint256 count = uint256(rawCount);

        // Assumption: prior batches initialized every ID below cursor and recorded a feasible aggregate weight.
        vm.assume(uint256(priorWeight) <= (cursor - 1) * router.MAX_MULTIPLIER_BPS());
        router.harnessSeedBootstrap(cursor, uint256(priorWeight));
        // Enumerate the same symbolic domain to keep each loop bound concrete for the prover.
        uint256 initializedCount;
        uint256 nextId;
        if (count == 1) (initializedCount, nextId) = router.bootstrapOperators(1);
        else if (count == 2) (initializedCount, nextId) = router.bootstrapOperators(2);
        else (initializedCount, nextId) = router.bootstrapOperators(3);

        assertEq(initializedCount, count);
        assertEq(nextId, cursor + count);
        assertEq(router.nextOperatorId(), cursor + count);
        assertEq(router.totalEffectiveWeight(), uint256(priorWeight));
        _assertInitialized(cursor);
        _assertInitialized(cursor + count - 1);
        _assertUninitialized(cursor + count);
    }

    function check_bootstrapClampsAtCollectionEnd(uint8 rawCount) public {
        _deployBootstrapSystem();
        uint256 cursor = router.LAST_OPERATOR_ID() - 2;
        vm.assume(rawCount >= 1 && rawCount <= router.MAX_BOOTSTRAP_BATCH());
        uint256 count = uint256(rawCount);
        uint256 expectedCount = count < 3 ? count : 3;
        router.harnessSeedBootstrap(cursor, 0);

        (uint256 initializedCount, uint256 nextId) = router.bootstrapOperators(count);

        assertEq(initializedCount, expectedCount);
        assertEq(nextId, cursor + expectedCount);
        if (count >= 3) assertEq(nextId, router.LAST_OPERATOR_ID() + 1);
        assertEq(router.nextOperatorId(), nextId);
        _assertInitialized(cursor);
        _assertInitialized(cursor + expectedCount - 1);
    }

    function check_bootstrapRejectsZeroCount() public {
        _deployBootstrapSystem();
        (bool success,) = address(router).call(abi.encodeCall(router.bootstrapOperators, (0)));
        assertFalse(success);
        assertEq(router.nextOperatorId(), router.FIRST_OPERATOR_ID());
        assertEq(router.totalEffectiveWeight(), 0);
    }

    function check_bootstrapRejectsCountAbove100(uint8 rawCount) public {
        _deployBootstrapSystem();
        vm.assume(rawCount > router.MAX_BOOTSTRAP_BATCH());
        uint256 count = uint256(rawCount);
        (bool success,) = address(router).call(abi.encodeCall(router.bootstrapOperators, (count)));
        assertFalse(success);
        assertEq(router.nextOperatorId(), router.FIRST_OPERATOR_ID());
        assertEq(router.totalEffectiveWeight(), 0);
    }

    function _deployLifecycleSystem() internal {
        _deployBootstrapSystem();
        collection.setOwner(1, ALICE);
        collection.setOwner(2, BOB);
        router.bootstrapOperators(2);
        router.harnessFinalizeBoundedBootstrap();
        assertEq(router.totalEffectiveWeight(), 20_000);
    }

    function _deployBootstrapSystem() internal {
        vault = new MockVault();
        collection = new MockOperatorCollection(address(vault));
        registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));
        timelock = new RouterLifecycleTimelockHarness(PROPOSER, EXECUTOR);
        router = new RouterLifecycleHarness(address(collection), address(registry), address(vault), address(timelock));
    }

    function _register(FormalBoundaryToken token) internal {
        vm.prank(PROPOSER);
        router.registerRewardAsset(address(token));
    }

    function _setEnabled(FormalBoundaryToken token, bool enabled) internal {
        vm.prank(PROPOSER);
        router.setRewardAssetEnabled(address(token), enabled);
    }

    function _add(FormalBoundaryToken token, uint256 amount) internal {
        token.mint(address(this), amount);
        token.approve(address(router), amount);
        router.addRewards(address(token), amount);
    }

    function _callAs(address caller, address target, bytes memory data) internal returns (bool success) {
        vm.prank(caller);
        (success,) = target.call(data);
    }

    function _call(address target, bytes memory data) internal returns (bool success) {
        (success,) = target.call(data);
    }

    function _callAsTimelock(bytes memory data) internal returns (bool success) {
        (success,) = timelock.callAsTimelock(address(router), data);
    }

    function _liability(FormalBoundaryToken token) internal view returns (uint256 liability) {
        (,,,, liability,,,,) = router.rewardBook(address(token));
    }

    function _assertInitialized(uint256 operatorId) internal view {
        (,,, bool initialized) = router.operatorState(operatorId);
        assertTrue(initialized);
    }

    function _assertUninitialized(uint256 operatorId) internal view {
        (,,, bool initialized) = router.operatorState(operatorId);
        assertFalse(initialized);
    }
}
