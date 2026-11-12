// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {MockActivationRegistry, MockAuthority, MockOperatorCollection, MockVault} from "./mocks/MockOperatorSystem.sol";

abstract contract MaximumBootstrapFixture is Test {
    MockOperatorCollection internal collection;
    MockActivationRegistry internal registry;
    OperatorFeeRouter internal router;
    address internal owner;

    function _priorBatches() internal pure virtual returns (uint256) {
        return 0;
    }

    function setUp() public {
        owner = makeAddr("bootstrap-owner");
        MockVault vault = new MockVault();
        collection = new MockOperatorCollection(address(vault));
        registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));
        for (uint256 id = 1; id <= 5_555; ++id) {
            collection.setOwner(id, owner);
            registry.setMultiplier(id, 12_500);
        }
        router =
            new OperatorFeeRouter(address(collection), address(registry), address(vault), address(new MockAuthority()));
        for (uint256 i; i < _priorBatches(); ++i) {
            router.bootstrapOperators(100);
        }
    }

    function _assertBatch() internal {
        uint256 cursor = router.nextOperatorId();
        vm.cool(address(collection));
        vm.cool(address(registry));
        vm.cool(address(router));
        uint256 start = gasleft();
        (uint256 count, uint256 next) = router.bootstrapOperators(100);
        uint256 used = start - gasleft();
        emit log_named_uint("standalone cold bootstrap batch gas", used);
        assertLt(used, 5_000_000);
        assertEq(count, cursor == 5_501 ? 55 : 100);
        assertEq(next, cursor + count);
        assertEq(router.totalEffectiveWeight(), (next - 1) * 12_500);
    }
}

contract OperatorFeeRouterBootstrapGasTest is MaximumBootstrapFixture {
    function testGas_StandaloneFirstBatch() public {
        _assertBatch();
    }

    function testGas_AllActiveMaximumWeightBootstrap() public {
        uint256 largestBatch;
        for (uint256 batch; batch < 56; ++batch) {
            vm.cool(address(collection));
            vm.cool(address(registry));
            vm.cool(address(router));
            uint256 start = gasleft();
            (uint256 count, uint256 next) = router.bootstrapOperators(100);
            uint256 used = start - gasleft();
            if (used > largestBatch) largestBatch = used;
            assertLt(used, 5_000_000);
            assertEq(count, batch == 55 ? 55 : 100);
            assertEq(next, batch == 55 ? 5_556 : (batch + 1) * 100 + 1);
            assertEq(router.totalEffectiveWeight(), (next - 1) * 12_500);
        }
        router.finalizeBootstrap();
        assertTrue(router.bootstrapFinalized());
        assertEq(router.totalEffectiveWeight(), 69_437_500);
        for (uint256 id = 1; id <= 5_555; ++id) {
            (address actualOwner, uint16 multiplier, uint16 weight, bool initialized) = router.operatorState(id);
            assertEq(actualOwner, owner);
            assertEq(multiplier, 12_500);
            assertEq(weight, 12_500);
            assertTrue(initialized);
        }
        emit log_named_uint("largest cold maximum-weight bootstrap batch gas", largestBatch);
    }
}

contract OperatorFeeRouterMiddleBootstrapGasTest is MaximumBootstrapFixture {
    function _priorBatches() internal pure override returns (uint256) {
        return 27;
    }

    function testGas_StandaloneMiddleBatch() public {
        _assertBatch();
    }
}

contract OperatorFeeRouterLastBootstrapGasTest is MaximumBootstrapFixture {
    function _priorBatches() internal pure override returns (uint256) {
        return 55;
    }

    function testGas_StandaloneFinalBatch() public {
        _assertBatch();
    }
}
