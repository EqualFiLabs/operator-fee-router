// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

/// @notice Minimal read-only interface consumed from the canonical activation registry.
interface IActivationRegistry {
    function genesisCollection() external view returns (address);
    function multiplierBps(uint256 operatorId) external view returns (uint16);
}
