// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {LibIndexMath} from "../../src/libraries/LibIndexMath.sol";

contract IndexMathHalmosTest is Test {
    uint256 internal constant RAY = 1e27;
    uint256 internal constant MIN_TOTAL_WEIGHT = 10_000;
    uint256 internal constant MAX_TOTAL_WEIGHT = 69_437_500;

    function test_IndexMathRepresentative() public pure {
        (uint256 delta, uint256 remainder) = LibIndexMath.indexDelta(123 ether, RAY / 3, 22_500, 7_111);
        assertEq(delta * 22_500 + remainder, 123 ether * RAY + RAY / 3 + 7_111);
        assertLt(remainder, 22_500);
    }

    function testFuzz_IndexMathConservesAcrossAggregateWeights(
        uint96 amount,
        uint96 rawScaledRemainderRay,
        uint32 rawDenominator,
        uint32 rawPriorIndexRemainder
    ) public pure {
        uint256 scaledRemainderRay = uint256(rawScaledRemainderRay) % RAY;
        uint256 denominator = bound(uint256(rawDenominator), MIN_TOTAL_WEIGHT, MAX_TOTAL_WEIGHT);
        uint256 priorIndexRemainder = uint256(rawPriorIndexRemainder) % MAX_TOTAL_WEIGHT;

        _assertConservation(amount, scaledRemainderRay, denominator, priorIndexRemainder);
    }

    function _assertConservation(
        uint96 amount,
        uint256 scaledRemainderRay,
        uint256 denominator,
        uint256 priorIndexRemainder
    ) internal pure {
        (uint256 delta, uint256 remainder) =
            LibIndexMath.indexDelta(amount, scaledRemainderRay, denominator, priorIndexRemainder);
        uint256 inputNumerator = uint256(amount) * RAY + scaledRemainderRay + priorIndexRemainder;

        assertEq(delta * denominator + remainder, inputNumerator);
        assertLt(remainder, denominator);
    }
}
