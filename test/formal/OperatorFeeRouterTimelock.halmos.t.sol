// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {OperatorFeeRouterTimelock} from "../../src/OperatorFeeRouterTimelock.sol";

contract OperatorFeeRouterTimelockHarness is OperatorFeeRouterTimelock {
    constructor(address proposer) OperatorFeeRouterTimelock(_singleton(proposer), new address[](0)) {}

    function updateDelayAsTimelock(uint256 newDelay) external returns (bool success) {
        (success,) = address(this).call(abi.encodeWithSelector(this.updateDelay.selector, newDelay));
    }

    function grantRoleAsTimelock(bytes32 role, address account) external returns (bool success) {
        (success,) = address(this).call(abi.encodeCall(this.grantRole, (role, account)));
    }

    function revokeRoleAsTimelock(bytes32 role, address account) external returns (bool success) {
        (success,) = address(this).call(abi.encodeCall(this.revokeRole, (role, account)));
    }

    function _singleton(address account) private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }
}

contract OperatorFeeRouterTimelockHalmosTest is Test {
    uint256 internal constant MIN_DELAY = 24 hours;
    address internal constant INITIAL_PROPOSER = address(0x1111);
    address internal constant ROTATED_PROPOSER = address(0x2222);

    OperatorFeeRouterTimelockHarness internal timelock;

    function setUp() public {
        timelock = new OperatorFeeRouterTimelockHarness(INITIAL_PROPOSER);
    }

    function check_delayNeverFallsBelow24Hours(uint256 newDelay) public {
        bool success = timelock.updateDelayAsTimelock(newDelay);
        uint256 resultingDelay = timelock.getMinDelay();

        assert(resultingDelay >= MIN_DELAY);
        if (newDelay < MIN_DELAY) {
            assert(!success);
            assert(resultingDelay == MIN_DELAY);
        } else {
            assert(success);
            assert(resultingDelay == newDelay);
        }
    }

    function check_constructorCouplesProposerAndCanceller() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), INITIAL_PROPOSER));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), INITIAL_PROPOSER));
    }

    function check_proposerGrantAlsoGrantsCanceller() public {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        assertTrue(timelock.grantRoleAsTimelock(proposerRole, ROTATED_PROPOSER));
        assertTrue(timelock.hasRole(proposerRole, ROTATED_PROPOSER));
        assertTrue(timelock.hasRole(cancellerRole, ROTATED_PROPOSER));
    }

    function check_proposerRevokeAlsoRevokesCanceller() public {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        assertTrue(timelock.grantRoleAsTimelock(proposerRole, ROTATED_PROPOSER));

        assertTrue(timelock.revokeRoleAsTimelock(proposerRole, ROTATED_PROPOSER));
        assertFalse(timelock.hasRole(proposerRole, ROTATED_PROPOSER));
        assertFalse(timelock.hasRole(cancellerRole, ROTATED_PROPOSER));
    }

    function check_proposerRenounceAlsoRenouncesCanceller() public {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        assertTrue(timelock.grantRoleAsTimelock(proposerRole, ROTATED_PROPOSER));

        vm.prank(ROTATED_PROPOSER);
        timelock.renounceRole(proposerRole, ROTATED_PROPOSER);

        assertFalse(timelock.hasRole(proposerRole, ROTATED_PROPOSER));
        assertFalse(timelock.hasRole(cancellerRole, ROTATED_PROPOSER));
    }
}
