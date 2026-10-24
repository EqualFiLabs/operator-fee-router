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
}
