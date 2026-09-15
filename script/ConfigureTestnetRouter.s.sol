// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {TestnetRouterAdmin} from "../src/testnet/TestnetRouterAdmin.sol";

/// @notice Bootstraps the disposable Router and enables the Lottery rehearsal assets.
contract ConfigureTestnetRouter is Script {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316;
    address internal constant WETH = 0x33e4191705c386532ba27cBF171Db86919200B94;
    address internal constant STATICS = 0xb6Cc79B2d892798d8e469A1efBF0713Fc2e51f86;

    bytes32 internal constant WETH_CODEHASH = 0x55f8ac53c64450f01880d8249fc5cb0c69c064e4bcb097ea80a02fff40485a7c;
    bytes32 internal constant STATICS_CODEHASH = 0xe548428d65bf2a8cee29a63e8dfaaeda0b4d44294d80f67f7626e1da8b89be69;

    error ConfigurationMismatch();
    error DependencyCodeHashMismatch(address dependency, bytes32 expected, bytes32 actual);
    error UnexpectedDeployer(address actual);
    error WrongChain(uint256 actual);

    function run() external {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        _requireCodeHash(WETH, WETH_CODEHASH);
        _requireCodeHash(STATICS, STATICS_CODEHASH);

        uint256 deployerKey = vm.envUint("ROUTER_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert UnexpectedDeployer(deployer);

        TestnetRouterAdmin admin = TestnetRouterAdmin(vm.envAddress("TESTNET_ROUTER_ADMIN"));
        OperatorFeeRouter router = OperatorFeeRouter(payable(vm.envAddress("OPERATOR_FEE_ROUTER")));
        if (admin.owner() != deployer || admin.router() != address(router) || router.routerTimelock() != address(admin))
        {
            revert ConfigurationMismatch();
        }

        vm.startBroadcast(deployerKey);
        if (!router.bootstrapFinalized()) {
            while (router.nextOperatorId() <= router.LAST_OPERATOR_ID()) {
                router.bootstrapOperators(router.MAX_BOOTSTRAP_BATCH());
            }
            router.finalizeBootstrap();
        }
        _enableAsset(admin, router, WETH);
        _enableAsset(admin, router, STATICS);
        vm.stopBroadcast();
    }

    function _enableAsset(TestnetRouterAdmin admin, OperatorFeeRouter router, address asset) private {
        if (!router.isRewardAsset(asset)) {
            admin.registerRewardAsset(asset);
        } else if (!router.rewardAssetEnabled(asset)) {
            admin.setRewardAssetEnabled(asset, true);
        }
    }

    function _requireCodeHash(address dependency, bytes32 expected) private view {
        bytes32 actual = keccak256(dependency.code);
        if (actual != expected) {
            revert DependencyCodeHashMismatch(dependency, expected, actual);
        }
    }
}
