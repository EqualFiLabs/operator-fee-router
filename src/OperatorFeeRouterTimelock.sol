// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Dedicated governance surface for Operator Fee Router configuration.
/// @dev No temporary admin is granted; role administration is timelocked from deployment.
contract OperatorFeeRouterTimelock is TimelockController {
    uint256 public constant MIN_DELAY = 24 hours;

    error TimelockDelayBelowMinimum(uint256 requested, uint256 minimum);

    constructor(address[] memory proposers, address[] memory executors)
        TimelockController(MIN_DELAY, proposers, executors, address(0))
    {}

    /// @notice Delay changes remain self-administered and cannot reduce the response window below 24 hours.
    function updateDelay(uint256 newDelay) public override {
        if (newDelay < MIN_DELAY) revert TimelockDelayBelowMinimum(newDelay, MIN_DELAY);
        super.updateDelay(newDelay);
    }
}
