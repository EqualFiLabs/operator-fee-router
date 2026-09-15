// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {TestnetRouterAdmin} from "../src/testnet/TestnetRouterAdmin.sol";

/// @notice Read-only validation of the historical Robinhood Testnet Router rehearsal.
contract ValidateRobinhoodTestnetRouter is Script {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_OWNER = 0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316;
    address internal constant OPERATOR_COLLECTION = 0x6c9197347161FC140a209175849d443FeaAF509c;
    address internal constant ACTIVATION_REGISTRY = 0x8cE462A801726FA030e06264f3423Be2Ae8d6414;
    address internal constant OPERATOR_VAULT = 0x8D3a32ddF8bD529EC847457eC79620D2870FFdc4;
    address internal constant ADMIN = 0x79c89f35d60fC2C0aEC9F5bB6D0B34d4c4B6dB87;
    address internal constant ROUTER = 0xE7Bb1D2766377984546611291732cED1833C0c36;
    address internal constant WETH = 0x33e4191705c386532ba27cBF171Db86919200B94;
    address internal constant STATICS = 0xb6Cc79B2d892798d8e469A1efBF0713Fc2e51f86;

    bytes32 internal constant OPERATOR_COLLECTION_CODEHASH =
        0xec224f66ecfa265dd306c54b2b683ba96395cd8f822dd2d51f84a2bac9d62afa;
    bytes32 internal constant ACTIVATION_REGISTRY_CODEHASH =
        0xc4bf24efb6c99c95060186a30200b7ee952604d77b917d0dae2cde87e6419e82;
    bytes32 internal constant OPERATOR_VAULT_CODEHASH =
        0x34641b08c85d3dc3e9b94551cb3b7b8d3a664dd773504849aec07499db5bb660;
    bytes32 internal constant ADMIN_CODEHASH = 0x2ad320342a7fa2a96f6ca75f54dc05021bc82749d092264158aa635a1d7d59d7;
    bytes32 internal constant ROUTER_CODEHASH = 0x5a24031cd7a3a71fd9c284ce64a07ec9585a8e325c947342cdc5b68b600fd1b8;
    bytes32 internal constant WETH_CODEHASH = 0x55f8ac53c64450f01880d8249fc5cb0c69c064e4bcb097ea80a02fff40485a7c;
    bytes32 internal constant STATICS_CODEHASH = 0xe548428d65bf2a8cee29a63e8dfaaeda0b4d44294d80f67f7626e1da8b89be69;

    error CodeHashMismatch(address target, bytes32 expected, bytes32 actual);
    error StateMismatch();
    error WrongChain(uint256 actual);

    function run() external view {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        _requireCodeHash(OPERATOR_COLLECTION, OPERATOR_COLLECTION_CODEHASH);
        _requireCodeHash(ACTIVATION_REGISTRY, ACTIVATION_REGISTRY_CODEHASH);
        _requireCodeHash(OPERATOR_VAULT, OPERATOR_VAULT_CODEHASH);
        _requireCodeHash(ADMIN, ADMIN_CODEHASH);
        _requireCodeHash(ROUTER, ROUTER_CODEHASH);
        _requireCodeHash(WETH, WETH_CODEHASH);
        _requireCodeHash(STATICS, STATICS_CODEHASH);

        TestnetRouterAdmin admin = TestnetRouterAdmin(ADMIN);
        OperatorFeeRouter router = OperatorFeeRouter(payable(ROUTER));
        if (
            admin.owner() != EXPECTED_OWNER || admin.router() != ROUTER
                || address(router.operatorCollection()) != OPERATOR_COLLECTION
                || address(router.activationRegistry()) != ACTIVATION_REGISTRY
                || router.operatorVault() != OPERATOR_VAULT || router.routerTimelock() != ADMIN
                || !router.bootstrapFinalized() || router.nextOperatorId() != 5_556
                || router.totalEffectiveWeight() != 5_550_000 || !router.isRewardAsset(WETH)
                || !router.rewardAssetEnabled(WETH) || !router.isRewardAsset(STATICS)
                || !router.rewardAssetEnabled(STATICS)
        ) {
            revert StateMismatch();
        }
    }

    function _requireCodeHash(address target, bytes32 expected) private view {
        bytes32 actual = keccak256(target.code);
        if (actual != expected) revert CodeHashMismatch(target, expected, actual);
    }
}
