// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {OperatorFeeRouterTimelock} from "../../src/OperatorFeeRouterTimelock.sol";

contract OperatorFeeRouterTimelockHarness is OperatorFeeRouterTimelock {
    constructor() OperatorFeeRouterTimelock(new address[](0), new address[](0)) {}

    function updateDelayAsTimelock(uint256 newDelay) external returns (bool success) {
        (success,) = address(this).call(abi.encodeWithSelector(this.updateDelay.selector, newDelay));
    }
}

contract OperatorFeeRouterTimelockHalmosTest {
    uint256 internal constant MIN_DELAY = 24 hours;

    OperatorFeeRouterTimelockHarness internal timelock;

    function setUp() public {
        timelock = new OperatorFeeRouterTimelockHarness();
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
}
