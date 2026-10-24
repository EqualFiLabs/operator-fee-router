methods {
    function indexDelta(uint256, uint256, uint256, uint256) external returns (uint256, uint256) envfree;
}

rule validInputsNeverRevert(
    uint256 amount,
    uint256 scaledRemainderRay,
    uint256 denominator,
    uint256 priorIndexRemainder
) {
    require amount <= 79228162514264337593543950335;
    require scaledRemainderRay < 1000000000000000000000000000;
    require priorIndexRemainder < 69437500;
    require denominator >= 10000;
    require denominator <= 69437500;

    uint256 delta;
    uint256 remainder;
    delta, remainder = indexDelta@withrevert(
        amount,
        scaledRemainderRay,
        denominator,
        priorIndexRemainder
    );
    bool success = !lastReverted;

    assert success;
}

rule quotientAndRemainderReconstructInput(
    uint256 amount,
    uint256 scaledRemainderRay,
    uint256 denominator,
    uint256 priorIndexRemainder
) {
    require amount <= 79228162514264337593543950335;
    require scaledRemainderRay < 1000000000000000000000000000;
    require priorIndexRemainder < 69437500;
    require denominator >= 10000;
    require denominator <= 69437500;

    uint256 delta;
    uint256 remainder;
    delta, remainder = indexDelta@withrevert(
        amount,
        scaledRemainderRay,
        denominator,
        priorIndexRemainder
    );
    bool success = !lastReverted;

    mathint numerator =
        to_mathint(amount) * 1000000000000000000000000000
        + to_mathint(scaledRemainderRay)
        + to_mathint(priorIndexRemainder);

    assert success;
    assert success =>
        to_mathint(delta) * to_mathint(denominator) + to_mathint(remainder) == numerator;
}

rule remainderIsNormalized(
    uint256 amount,
    uint256 scaledRemainderRay,
    uint256 denominator,
    uint256 priorIndexRemainder
) {
    require amount <= 79228162514264337593543950335;
    require scaledRemainderRay < 1000000000000000000000000000;
    require priorIndexRemainder < 69437500;
    require denominator >= 10000;
    require denominator <= 69437500;

    uint256 delta;
    uint256 remainder;
    delta, remainder = indexDelta@withrevert(
        amount,
        scaledRemainderRay,
        denominator,
        priorIndexRemainder
    );
    bool success = !lastReverted;

    assert success;
    assert success => remainder < denominator;
}

rule zeroDenominatorReverts(
    uint256 amount,
    uint256 scaledRemainderRay,
    uint256 priorIndexRemainder
) {
    require amount <= 79228162514264337593543950335;
    require scaledRemainderRay < 1000000000000000000000000000;
    require priorIndexRemainder < 69437500;

    uint256 delta;
    uint256 remainder;
    delta, remainder = indexDelta@withrevert(amount, scaledRemainderRay, 0, priorIndexRemainder);
    bool success = !lastReverted;

    assert !success;
}
