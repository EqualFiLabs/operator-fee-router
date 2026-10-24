// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {TestnetRouterAdmin} from "../src/testnet/TestnetRouterAdmin.sol";

contract RouterAdminTarget {
    address public lastAsset;
    bool public lastEnabled;

    function registerRewardAsset(address asset) external {
        lastAsset = asset;
        lastEnabled = true;
    }

    function setRewardAssetEnabled(address asset, bool enabled) external {
        lastAsset = asset;
        lastEnabled = enabled;
    }
}

contract TestnetRouterAdminTest is Test {
    address internal constant HISTORICAL_OWNER = 0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316;
    bytes32 internal constant HISTORICAL_RUNTIME_HASH =
        0x2ad320342a7fa2a96f6ca75f54dc05021bc82749d092264158aa635a1d7d59d7;

    address internal owner = makeAddr("owner");
    address internal outsider = makeAddr("outsider");
    address internal asset = makeAddr("asset");

    TestnetRouterAdmin internal admin;
    RouterAdminTarget internal target;

    function setUp() public {
        vm.chainId(46_630);
        admin = new TestnetRouterAdmin(owner);
        target = new RouterAdminTarget();
    }

    function test_ReproducesHistoricalRuntimeHash() public {
        TestnetRouterAdmin historical = new TestnetRouterAdmin(HISTORICAL_OWNER);
        assertEq(address(historical).codehash, HISTORICAL_RUNTIME_HASH);
    }

    function test_BindsOneRouterAndForwardsOnlyForOwner() public {
        vm.prank(owner);
        admin.bindRouter(address(target));
        assertEq(admin.router(), address(target));

        vm.prank(owner);
        admin.registerRewardAsset(asset);
        assertEq(target.lastAsset(), asset);
        assertTrue(target.lastEnabled());

        vm.prank(owner);
        admin.setRewardAssetEnabled(asset, false);
        assertFalse(target.lastEnabled());

        vm.expectRevert(TestnetRouterAdmin.AlreadyBound.selector);
        vm.prank(owner);
        admin.bindRouter(address(target));

        vm.expectRevert(abi.encodeWithSelector(TestnetRouterAdmin.NotOwner.selector, outsider));
        vm.prank(outsider);
        admin.registerRewardAsset(asset);
    }

    function test_RejectsUnauthorizedBindingAndForwarding() public {
        vm.expectRevert(abi.encodeWithSelector(TestnetRouterAdmin.NotOwner.selector, outsider));
        vm.prank(outsider);
        admin.bindRouter(address(target));

        vm.expectRevert(abi.encodeWithSelector(TestnetRouterAdmin.NotOwner.selector, outsider));
        vm.prank(outsider);
        admin.setRewardAssetEnabled(asset, true);
    }

    function test_RejectsWrongChainAndInvalidAddresses() public {
        vm.expectRevert(TestnetRouterAdmin.InvalidAddress.selector);
        new TestnetRouterAdmin(address(0));

        vm.expectRevert(TestnetRouterAdmin.InvalidAddress.selector);
        vm.prank(owner);
        admin.bindRouter(address(0));

        vm.expectRevert(TestnetRouterAdmin.InvalidAddress.selector);
        vm.prank(owner);
        admin.registerRewardAsset(asset);

        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(TestnetRouterAdmin.WrongChain.selector, 1));
        new TestnetRouterAdmin(owner);
    }
}
