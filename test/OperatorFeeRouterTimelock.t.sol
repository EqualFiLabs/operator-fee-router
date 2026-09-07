// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {OperatorFeeRouterTimelock} from "../src/OperatorFeeRouterTimelock.sol";
import {MockActivationRegistry, MockOperatorCollection, MockVault} from "./mocks/MockOperatorSystem.sol";
import {MockERC20} from "./mocks/MockTokens.sol";

contract OperatorFeeRouterTimelockTest is Test {
    uint256 internal constant DELAY = 24 hours;

    address internal proposer = makeAddr("proposer");
    MockVault internal vault;
    MockOperatorCollection internal collection;
    MockActivationRegistry internal registry;
    OperatorFeeRouterTimelock internal timelock;
    OperatorFeeRouter internal router;
    MockERC20 internal token;

    function setUp() public {
        vault = new MockVault();
        collection = new MockOperatorCollection(address(vault));
        registry = new MockActivationRegistry(address(collection));
        collection.bindActivationRegistry(address(registry));

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new OperatorFeeRouterTimelock(proposers, executors);
        router = new OperatorFeeRouter(address(collection), address(registry), address(vault), address(timelock));
        token = new MockERC20("Timelocked Reward", "TLR");
    }

    function test_TimelockHasNoTemporaryAdminAndOpenExecution() public view {
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), proposer));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), proposer));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
        assertEq(timelock.getMinDelay(), DELAY);
    }

    function test_AssetRegistrationRequiresScheduledTimelockExecution() public {
        vm.expectRevert(abi.encodeWithSelector(OperatorFeeRouter.Unauthorized.selector, address(this)));
        router.registerRewardAsset(address(token));

        bytes memory data = abi.encodeCall(OperatorFeeRouter.registerRewardAsset, (address(token)));
        bytes32 salt = keccak256("register reward token");
        vm.prank(proposer);
        timelock.schedule(address(router), 0, data, bytes32(0), salt, DELAY);

        vm.expectRevert();
        timelock.execute(address(router), 0, data, bytes32(0), salt);

        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(router), 0, data, bytes32(0), salt);
        assertTrue(router.isRewardAsset(address(token)));
        assertTrue(router.rewardAssetEnabled(address(token)));
    }

    function test_TimelockCannotReduceDelayBelow24Hours() public {
        uint256 unsafeDelay = DELAY - 1;
        bytes memory data = abi.encodeCall(OperatorFeeRouterTimelock.updateDelay, (unsafeDelay));
        bytes32 salt = keccak256("unsafe delay");
        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY);
        vm.expectRevert(
            abi.encodeWithSelector(OperatorFeeRouterTimelock.TimelockDelayBelowMinimum.selector, unsafeDelay, DELAY)
        );
        timelock.execute(address(timelock), 0, data, bytes32(0), salt);
        assertEq(timelock.getMinDelay(), DELAY);
    }
}
