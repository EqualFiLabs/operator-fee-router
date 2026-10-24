methods {
    function settlementDelta(uint16, uint256, uint256) external returns (uint256, uint256) envfree;
}

rule validSettlementInputsNeverRevert(
    uint16 weight,
    uint256 indexDeltaRay,
    uint256 priorRemainderRay
) {
    require weight <= 12500;
    require priorRemainderRay < 1000000000000000000000000000;
    require to_mathint(weight) * indexDeltaRay + priorRemainderRay
        <= 79228162514264337593543950335 * 1000000000000000000000000000;

    uint256 newlyAccrued;
    uint256 remainderRay;
    newlyAccrued, remainderRay = settlementDelta@withrevert(weight, indexDeltaRay, priorRemainderRay);
    bool success = !lastReverted;
    assert success;
}

rule settlementQuotientAndRemainderReconstructInput(
    uint16 weight,
    uint256 indexDeltaRay,
    uint256 priorRemainderRay
) {
    require weight <= 12500;
    require priorRemainderRay < 1000000000000000000000000000;
    mathint numerator = to_mathint(weight) * indexDeltaRay + priorRemainderRay;
    require numerator <= 79228162514264337593543950335 * 1000000000000000000000000000;

    uint256 newlyAccrued;
    uint256 remainderRay;
    newlyAccrued, remainderRay = settlementDelta@withrevert(weight, indexDeltaRay, priorRemainderRay);
    bool success = !lastReverted;
    assert success;
    assert to_mathint(newlyAccrued) * 1000000000000000000000000000 + remainderRay == numerator;
}

rule settlementRemainderIsNormalized(
    uint16 weight,
    uint256 indexDeltaRay,
    uint256 priorRemainderRay
) {
    require weight <= 12500;
    require priorRemainderRay < 1000000000000000000000000000;
    require to_mathint(weight) * indexDeltaRay + priorRemainderRay
        <= 79228162514264337593543950335 * 1000000000000000000000000000;

    uint256 newlyAccrued;
    uint256 remainderRay;
    newlyAccrued, remainderRay = settlementDelta@withrevert(weight, indexDeltaRay, priorRemainderRay);
    bool success = !lastReverted;
    assert success;
    assert remainderRay < 1000000000000000000000000000;
}
