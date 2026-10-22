// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {MockActivationRegistry, MockAuthority, MockOperatorCollection, MockVault} from "./mocks/MockOperatorSystem.sol";
import {MockERC20} from "./mocks/MockTokens.sol";
import {OperatorFeeRouterHarness} from "./mocks/OperatorFeeRouterHarness.sol";

abstract contract OperatorFeeRouterGasFixture is Test {
    uint256 internal constant MAX_CHANGED_SYNC_GAS = 10_000_000;
    address internal alice = makeAddr("gas-alice");
    address internal bob = makeAddr("gas-bob");
    address internal carol = makeAddr("gas-carol");
    address internal contributor = makeAddr("gas-contributor");
    MockVault internal vault;
    MockOperatorCollection internal collection;
    MockActivationRegistry internal registry;
    OperatorFeeRouterHarness internal router;
    MockERC20[] internal tokens;

    function _assetCount() internal pure virtual returns (uint256);

    function setUp() public virtual {
        vault = new MockVault();
        MockAuthority timelock = new MockAuthority();
        collection = new MockOperatorCollection(address(vault));
        registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));
        collection.setOwner(1, alice);
        collection.setOwner(2, bob);
        registry.setMultiplier(2, 12_500);
        router = new OperatorFeeRouterHarness(address(collection), address(registry), address(vault), address(timelock));
        router.bootstrapOperators(2);
        router.harnessFinalizeBootstrap();

        for (uint256 i; i < _assetCount(); ++i) {
            MockERC20 token = new MockERC20("Gas Reward", "GAS");
            tokens.push(token);
            vm.prank(address(timelock));
            router.registerRewardAsset(address(token));
            // Non-exact division exercises fractional settlement and redistribution storage writes.
            uint256 amount = 2 ether + 1;
            token.mint(contributor, amount);
            vm.startPrank(contributor);
            token.approve(address(router), amount);
            router.addRewards(address(token), amount);
            vm.stopPrank();
        }
        collection.setOwner(1, carol);
    }

    function _coolDependencies() internal {
        vm.cool(address(registry));
        vm.cool(address(collection));
        vm.cool(address(router));
    }
}

abstract contract OperatorFeeRouterTransferGasFixture is OperatorFeeRouterGasFixture {
    function testGas_ColdFractionalTransferSync() public {
        _coolDependencies();
        uint256 gasBefore = gasleft();
        router.syncOperator(1);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint(
            string.concat("cold fractional sync gas (", vm.toString(_assetCount()), " assets)"), gasUsed
        );
        assertLt(gasUsed, MAX_CHANGED_SYNC_GAS);
    }
}

contract OperatorFeeRouter8AssetGasTest is OperatorFeeRouterTransferGasFixture {
    function _assetCount() internal pure override returns (uint256) {
        return 8;
    }
}

contract OperatorFeeRouter16AssetGasTest is OperatorFeeRouterTransferGasFixture {
    function _assetCount() internal pure override returns (uint256) {
        return 16;
    }
}

contract OperatorFeeRouter32AssetGasTest is OperatorFeeRouterTransferGasFixture {
    function _assetCount() internal pure override returns (uint256) {
        return 32;
    }
}

contract OperatorFeeRouterGasTest is OperatorFeeRouterTransferGasFixture {
    function _assetCount() internal pure override returns (uint256) {
        return 64;
    }

    function testGas_ColdClaimTriggeredTransferWith64Assets() public {
        address asset = address(tokens[0]);
        _coolDependencies();
        vm.prank(carol);
        uint256 gasBefore = gasleft();
        uint256 claimed = router.claimOperatorRewards(1, asset, carol);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("cold claim-triggered transfer sync gas (64 assets)", gasUsed);
        assertEq(claimed, 0);
        assertLt(gasUsed, MAX_CHANGED_SYNC_GAS);
    }
}

contract OperatorFeeRouterQueuedGasTest is OperatorFeeRouterGasFixture {
    function _assetCount() internal pure override returns (uint256) {
        return 64;
    }

    function setUp() public override {
        super.setUp();
        collection.setOwner(2, address(vault));
        router.syncOperator(2);
    }

    function testGas_ColdQueuedForfeitureWith64Assets() public {
        _coolDependencies();
        uint256 gasBefore = gasleft();
        router.syncOperator(1);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("cold queued forfeiture sync gas (64 assets)", gasUsed);
        assertLt(gasUsed, MAX_CHANGED_SYNC_GAS);
        for (uint256 i; i < tokens.length; ++i) {
            (uint256 amount,) = router.pendingForfeiture(1, address(tokens[i]));
            assertGt(amount, 0);
        }
    }
}
