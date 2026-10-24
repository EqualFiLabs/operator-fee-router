methods {
    function OperatorFeeRouter._settlementDelta(
        uint16 weight,
        uint256 indexDeltaRay,
        uint256 priorRemainderRay
    ) internal returns (uint256, uint256)
        => cvlSettlementDelta(weight, indexDeltaRay, priorRemainderRay);

    function LibIndexMath.indexDelta(
        uint256 amount,
        uint256 scaledRemainderRay,
        uint256 denominator,
        uint256 priorIndexRemainder
    ) internal returns (uint256, uint256)
        => cvlIndexDelta(amount, scaledRemainderRay, denominator, priorIndexRemainder);
}

// These summaries compose the router proofs with the separately proved production arithmetic
// helpers. Assertions expose any caller outside the proved domains instead of excluding it.
function cvlSettlementDelta(uint16 weight, uint256 indexDeltaRay, uint256 priorRemainderRay)
    returns (uint256, uint256)
{
    assert weight <= 12500, "settlement summary weight domain";
    assert priorRemainderRay < 1000000000000000000000000000,
        "settlement summary prior remainder domain";

    mathint numerator = to_mathint(weight) * indexDeltaRay + priorRemainderRay;
    assert numerator
        <= 79228162514264337593543950335 * 1000000000000000000000000000,
        "settlement summary scaled entitlement domain";

    uint256 newlyAccrued;
    uint256 remainderRay;
    require remainderRay < 1000000000000000000000000000;
    require to_mathint(newlyAccrued) * 1000000000000000000000000000 + remainderRay == numerator;
    return (newlyAccrued, remainderRay);
}

function cvlIndexDelta(
    uint256 amount,
    uint256 scaledRemainderRay,
    uint256 denominator,
    uint256 priorIndexRemainder
) returns (uint256, uint256) {
    assert amount <= 79228162514264337593543950335, "index summary amount domain";
    assert scaledRemainderRay < 1000000000000000000000000000,
        "index summary scaled remainder domain";
    assert denominator >= 10000 && denominator <= 37500, "index summary denominator domain";
    assert priorIndexRemainder < 37500, "index summary prior remainder domain";

    mathint numerator = to_mathint(amount) * 1000000000000000000000000000
        + scaledRemainderRay + priorIndexRemainder;
    assert numerator <= max_uint256, "index summary numerator domain";

    uint256 delta;
    uint256 remainder;
    require remainder < denominator;
    require to_mathint(delta) * denominator + remainder == numerator;
    return (delta, remainder);
}
