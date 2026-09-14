// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

/// @notice Stable integration surface for reward contributors and Operator holders.
interface IOperatorFeeRouter {
    function addRewards(address asset, uint256 amount) external;

    function syncOperator(uint256 operatorId) external returns (uint8 kind);

    function claimOperatorRewards(uint256 operatorId, address asset, address receiver) external returns (uint256 amount);

    function flushPendingForfeiture(uint256 operatorId, address asset)
        external
        returns (uint256 amount, uint256 remainderRay);

    function pendingOperatorRewards(uint256 operatorId, address asset) external view returns (uint256 amount);

    function effectiveWeight(uint256 operatorId) external view returns (uint256 weight);

    function syncedOwner(uint256 operatorId) external view returns (address owner);

    function syncedMultiplierBps(uint256 operatorId) external view returns (uint16 multiplierBps);

    function totalEffectiveWeight() external view returns (uint256 weight);

    function isRewardAsset(address asset) external view returns (bool);

    function rewardAssetEnabled(address asset) external view returns (bool);

    function rewardAssetCount() external view returns (uint256);

    function rewardAssetAt(uint256 index) external view returns (address);
}
