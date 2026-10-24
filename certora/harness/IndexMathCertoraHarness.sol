// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {LibIndexMath} from "../../src/libraries/LibIndexMath.sol";

contract IndexMathCertoraHarness {
    function indexDelta(uint256 amount, uint256 scaledRemainderRay, uint256 denominator, uint256 priorIndexRemainder)
        external
        pure
        returns (uint256 delta, uint256 remainder)
    {
        return LibIndexMath.indexDelta(amount, scaledRemainderRay, denominator, priorIndexRemainder);
    }
}
