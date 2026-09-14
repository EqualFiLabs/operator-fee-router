// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {OperatorFeeRouter} from "../../src/OperatorFeeRouter.sol";

contract OperatorFeeRouterHarness is OperatorFeeRouter {
    constructor(address collection, address registry, address vault, address timelock)
        OperatorFeeRouter(collection, registry, vault, timelock)
    {}

    function harnessFinalizeBootstrap() external {
        nextOperatorId = LAST_OPERATOR_ID + 1;
        bootstrapFinalized = true;
    }

    function harnessSetRewardIndex(address asset, uint256 indexRay) external {
        rewardBook[asset].indexRay = indexRay;
    }

    function harnessSetOperatorCheckpoint(uint256 operatorId, address asset, uint256 checkpointRay) external {
        operatorAssetState[operatorId][asset].checkpointRay = checkpointRay;
    }
}
