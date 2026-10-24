// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

interface ITestnetOperatorFeeRouterAdminTarget {
    function registerRewardAsset(address asset) external;
    function setRewardAssetEnabled(address asset, bool enabled) external;
}

/// @notice Disposable Robinhood Testnet-only authority for OperatorFeeRouter configuration.
/// @dev The production Router bytecode is unchanged. This helper replaces its 24-hour production
/// timelock only for the bounded release rehearsal and cannot target a second Router.
contract TestnetRouterAdmin {
    uint256 public constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;

    address public immutable owner;
    address public router;

    error AlreadyBound();
    error InvalidAddress();
    error NotOwner(address caller);
    error WrongChain(uint256 actual);

    constructor(address owner_) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        if (owner_ == address(0)) revert InvalidAddress();
        owner = owner_;
    }

    function bindRouter(address router_) external onlyOwner {
        if (router != address(0)) revert AlreadyBound();
        if (router_.code.length == 0) revert InvalidAddress();
        router = router_;
    }

    function registerRewardAsset(address asset) external onlyOwner {
        _router().registerRewardAsset(asset);
    }

    function setRewardAssetEnabled(address asset, bool enabled) external onlyOwner {
        _router().setRewardAssetEnabled(asset, enabled);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    function _router() private view returns (ITestnetOperatorFeeRouterAdminTarget target) {
        address router_ = router;
        if (router_ == address(0)) revert InvalidAddress();
        target = ITestnetOperatorFeeRouterAdminTarget(router_);
    }
}
