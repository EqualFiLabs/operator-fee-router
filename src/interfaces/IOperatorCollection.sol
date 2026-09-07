// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

/// @notice Minimal read-only interface consumed from the canonical Statics Operator NFT.
interface IOperatorCollection {
    function ownerOf(uint256 operatorId) external view returns (address);
    function COLLECTION_SIZE() external view returns (uint256);
    function vault() external view returns (address);
    function activationRegistry() external view returns (address);
}
