// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

/// @notice Full-precision reward-index numerator accounting.
library LibIndexMath {
    uint256 internal constant RAY = 1e27;

    /// @dev `scaledRemainderRay` is an additional sub-token numerator denominated in RAY units.
    function indexDelta(uint256 amount, uint256 scaledRemainderRay, uint256 denominator, uint256 priorIndexRemainder)
        internal
        pure
        returns (uint256 delta, uint256 remainder)
    {
        // Router accounting caps `amount` at uint96, so this complete numerator is below 2^187.
        uint256 numerator = amount * RAY + scaledRemainderRay + priorIndexRemainder;
        delta = numerator / denominator;
        remainder = numerator % denominator;
    }
}
