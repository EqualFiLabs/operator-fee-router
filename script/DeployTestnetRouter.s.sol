// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {TestnetRouterAdmin} from "../src/testnet/TestnetRouterAdmin.sol";

/// @notice Reproduces the disposable Router deployment used by the Statics Lottery rehearsal.
/// @dev Address derivation still depends on the broadcaster nonce; this script does not use CREATE2.
contract DeployTestnetRouter is Script {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316;
    address internal constant OPERATOR_COLLECTION = 0x6c9197347161FC140a209175849d443FeaAF509c;
    address internal constant ACTIVATION_REGISTRY = 0x8cE462A801726FA030e06264f3423Be2Ae8d6414;
    address internal constant OPERATOR_VAULT = 0x8D3a32ddF8bD529EC847457eC79620D2870FFdc4;

    bytes32 internal constant OPERATOR_COLLECTION_CODEHASH =
        0xec224f66ecfa265dd306c54b2b683ba96395cd8f822dd2d51f84a2bac9d62afa;
    bytes32 internal constant ACTIVATION_REGISTRY_CODEHASH =
        0xc4bf24efb6c99c95060186a30200b7ee952604d77b917d0dae2cde87e6419e82;
    bytes32 internal constant OPERATOR_VAULT_CODEHASH =
        0x34641b08c85d3dc3e9b94551cb3b7b8d3a664dd773504849aec07499db5bb660;

    error DependencyCodeHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error UnexpectedDeployer(address actual);
    error WrongChain(uint256 actual);

    function run() external returns (TestnetRouterAdmin admin, OperatorFeeRouter router) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        _requireCodeHash(OPERATOR_COLLECTION, OPERATOR_COLLECTION_CODEHASH);
        _requireCodeHash(ACTIVATION_REGISTRY, ACTIVATION_REGISTRY_CODEHASH);
        _requireCodeHash(OPERATOR_VAULT, OPERATOR_VAULT_CODEHASH);

        uint256 deployerKey = vm.envUint("ROUTER_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert UnexpectedDeployer(deployer);

        vm.startBroadcast(deployerKey);
        admin = new TestnetRouterAdmin(deployer);
        router = new OperatorFeeRouter(OPERATOR_COLLECTION, ACTIVATION_REGISTRY, OPERATOR_VAULT, address(admin));
        admin.bindRouter(address(router));
        vm.stopBroadcast();
    }

    function _requireCodeHash(address dependency, bytes32 expected) private view {
        bytes32 actual = keccak256(dependency.code);
        if (actual != expected) {
            revert DependencyCodeHashMismatch(dependency, expected, actual);
        }
    }
}
