// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {MockActivationRegistry, MockAuthority, MockOperatorCollection, MockVault} from "./mocks/MockOperatorSystem.sol";
import {MockERC20} from "./mocks/MockTokens.sol";
import {OperatorFeeRouterHarness} from "./mocks/OperatorFeeRouterHarness.sol";

contract OperatorFeeRouterGasTest is Test {
    uint256 internal constant MAX_CHANGED_SYNC_GAS = 10_000_000;

    address internal alice = makeAddr("gas-alice");
    address internal bob = makeAddr("gas-bob");
    address internal carol = makeAddr("gas-carol");
    address internal contributor = makeAddr("gas-contributor");

    function testGas_TransferSyncWith8Assets() public {
        _measureTransferSync(8);
    }

    function testGas_TransferSyncWith16Assets() public {
        _measureTransferSync(16);
    }

    function testGas_TransferSyncWith32Assets() public {
        _measureTransferSync(32);
    }

    function testGas_TransferSyncWith64Assets() public {
        _measureTransferSync(64);
    }

    function testGas_ClaimTriggeredTransferWith64Assets() public {
        (OperatorFeeRouterHarness router, MockOperatorCollection collection,, MockERC20[] memory tokens) =
            _configuredRouter(64);
        collection.setOwner(1, carol);

        uint256 gasBefore = gasleft();
        vm.prank(carol);
        uint256 claimed = router.claimOperatorRewards(1, address(tokens[0]), carol);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("claim-triggered transfer sync gas (64 assets)", gasUsed);
        assertEq(claimed, 0);
        assertLt(gasUsed, MAX_CHANGED_SYNC_GAS);
    }

    function _measureTransferSync(uint256 assetCount) internal {
        (OperatorFeeRouterHarness router, MockOperatorCollection collection,,) = _configuredRouter(assetCount);
        collection.setOwner(1, carol);

        uint256 gasBefore = gasleft();
        router.syncOperator(1);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint(string.concat("transfer sync gas (", vm.toString(assetCount), " assets)"), gasUsed);
        assertLt(gasUsed, MAX_CHANGED_SYNC_GAS);
    }

    function _configuredRouter(uint256 assetCount)
        internal
        returns (
            OperatorFeeRouterHarness router,
            MockOperatorCollection collection,
            MockActivationRegistry registry,
            MockERC20[] memory tokens
        )
    {
        MockVault vault = new MockVault();
        MockAuthority timelock = new MockAuthority();
        collection = new MockOperatorCollection(address(vault));
        registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));
        collection.setOwner(1, alice);
        collection.setOwner(2, bob);
        router = new OperatorFeeRouterHarness(address(collection), address(registry), address(vault), address(timelock));
        router.bootstrapOperators(2);
        router.harnessFinalizeBootstrap();

        tokens = new MockERC20[](assetCount);
        for (uint256 i; i < assetCount; ++i) {
            MockERC20 token = new MockERC20("Gas Reward", "GAS");
            tokens[i] = token;
            vm.prank(address(timelock));
            router.registerRewardAsset(address(token));
            token.mint(contributor, 2 ether);
            vm.startPrank(contributor);
            token.approve(address(router), 2 ether);
            router.addRewards(address(token), 2 ether);
            vm.stopPrank();
        }
    }
}
