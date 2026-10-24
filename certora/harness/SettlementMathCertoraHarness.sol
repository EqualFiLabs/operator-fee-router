// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {OperatorFeeRouter} from "../../src/OperatorFeeRouter.sol";

/// @notice Exposes the production settlement calculation for an isolated arithmetic proof.
contract SettlementMathCertoraHarness is OperatorFeeRouter {
    constructor(address system) OperatorFeeRouter(system, system, system, system) {
        // The Certora configuration deploys the linked constructor dependency at this address.
        require(system == address(0x1000), "formal system");
    }

    function settlementDelta(uint16 weight, uint256 indexDeltaRay, uint256 priorRemainderRay)
        external
        pure
        returns (uint256 newlyAccrued, uint256 remainderRay)
    {
        return _settlementDelta(weight, indexDeltaRay, priorRemainderRay);
    }
}
