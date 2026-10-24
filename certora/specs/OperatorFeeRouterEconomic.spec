import "OperatorFeeRouterConservation.spec";
import "helpers/RouterMathSummaries.spec";

// These invariants form one simultaneous induction proof and must be verified together.
use invariant accountingStateIsNormalized;
use invariant rewardAssetsEconomicConservation;
