// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {OperatorFeeRouter} from "../../src/OperatorFeeRouter.sol";
import {
    MockActivationRegistry,
    MockAuthority,
    MockOperatorCollection,
    MockVault
} from "../mocks/MockOperatorSystem.sol";
import {OperatorFeeRouterHarness} from "../mocks/OperatorFeeRouterHarness.sol";

contract OperatorSyncHalmosTest is Test {
    address internal alice;
    address internal bob;
    address internal carol;

    MockVault internal vault;
    MockAuthority internal timelock;
    MockOperatorCollection internal collection;
    MockActivationRegistry internal registry;
    OperatorFeeRouterHarness internal router;

    function _deploySystem() internal {
        alice = address(0x1111);
        bob = address(0x2222);
        carol = address(0x3333);
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
    }

    function check_equalSnapshotIsNoop() public {
        _deploySystem();
        uint256 totalWeightBefore = router.totalEffectiveWeight();
        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Noop));
        _assertInstalled(1, alice, 10_000, 10_000, totalWeightBefore);
    }

    function check_sameOwnerHigherMultiplierIsActivation(uint16 rawMultiplier) public {
        _deploySystem();
        uint16 multiplier = uint16(bound(rawMultiplier, 10_001, 12_500));
        uint256 totalWeightBefore = router.totalEffectiveWeight();
        registry.setMultiplier(1, multiplier);

        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Activation));
        _assertInstalled(1, alice, multiplier, multiplier, totalWeightBefore - 10_000 + multiplier);
    }

    function check_sameOwnerLowerMultiplierIsTransfer(uint16 rawMultiplier) public {
        _deploySystem();
        registry.setMultiplier(1, 12_500);
        router.syncOperator(1);
        uint16 multiplier = uint16(bound(rawMultiplier, 10_000, 12_499));
        uint256 totalWeightBefore = router.totalEffectiveWeight();
        registry.setMultiplier(1, multiplier);

        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Transfer));
        _assertInstalled(1, alice, multiplier, multiplier, totalWeightBefore - 12_500 + multiplier);
    }

    function check_ownerMismatchIsTransferAtEveryValidMultiplier(uint16 rawMultiplier) public {
        _deploySystem();
        uint16 multiplier = uint16(bound(rawMultiplier, 10_000, 12_500));
        uint256 totalWeightBefore = router.totalEffectiveWeight();
        collection.setOwner(1, carol);
        registry.setMultiplier(1, multiplier);

        assertEq(uint8(router.syncOperator(1)), uint8(OperatorFeeRouter.SyncKind.Transfer));
        _assertInstalled(1, carol, multiplier, multiplier, totalWeightBefore - 10_000 + multiplier);
    }

    function _assertInstalled(
        uint256 operatorId,
        address expectedOwner,
        uint16 expectedMultiplier,
        uint16 expectedWeight,
        uint256 expectedTotalWeight
    ) internal view {
        (address owner, uint16 multiplier, uint16 weight, bool initialized) = router.operatorState(operatorId);
        assertTrue(initialized);
        assertEq(owner, expectedOwner);
        assertEq(multiplier, expectedMultiplier);
        assertEq(weight, expectedWeight);
        assertEq(router.totalEffectiveWeight(), expectedTotalWeight);
    }
}
