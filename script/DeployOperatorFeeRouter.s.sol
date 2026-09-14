// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {OperatorFeeRouterTimelock} from "../src/OperatorFeeRouterTimelock.sol";

contract DeployOperatorFeeRouter is Script {
    uint256 internal constant ROBINHOOD_CHAIN_ID = 4_663;
    address internal constant OPERATOR_COLLECTION = 0xad5E9F96A91D1A6F550580b157af2068A0e8F0BE;
    address internal constant ACTIVATION_REGISTRY = 0xfC62e99CaE93878f83801f3d6Bb4f1762E720B30;
    address internal constant OPERATOR_VAULT = 0x8AAAF9a22f439589987B8f1e69d79ca4f648C297;

    error WrongChain(uint256 actual);
    error ZeroProposer();

    function run() external returns (OperatorFeeRouterTimelock timelock, OperatorFeeRouter router) {
        if (block.chainid != ROBINHOOD_CHAIN_ID) revert WrongChain(block.chainid);

        uint256 deployerKey = vm.envUint("OPERATOR_ROUTER_DEPLOYER_PRIVATE_KEY");
        address proposer = vm.envAddress("OPERATOR_ROUTER_TIMELOCK_PROPOSER");
        if (proposer == address(0)) revert ZeroProposer();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.startBroadcast(deployerKey);
        timelock = new OperatorFeeRouterTimelock(proposers, executors);
        router = new OperatorFeeRouter(OPERATOR_COLLECTION, ACTIVATION_REGISTRY, OPERATOR_VAULT, address(timelock));
        vm.stopBroadcast();

        _writeManifest(timelock, router, proposer);
    }

    function _writeManifest(OperatorFeeRouterTimelock timelock, OperatorFeeRouter router, address proposer) internal {
        string memory objectKey = "operatorFeeRouter";
        vm.serializeUint(objectKey, "chainId", block.chainid);
        vm.serializeAddress(objectKey, "operatorCollection", OPERATOR_COLLECTION);
        vm.serializeAddress(objectKey, "activationRegistry", ACTIVATION_REGISTRY);
        vm.serializeAddress(objectKey, "operatorVault", OPERATOR_VAULT);
        vm.serializeAddress(objectKey, "timelock", address(timelock));
        vm.serializeAddress(objectKey, "router", address(router));
        vm.serializeUint(objectKey, "timelockDelay", timelock.getMinDelay());
        vm.serializeAddress(objectKey, "timelockProposer", proposer);
        vm.serializeAddress(objectKey, "timelockExecutor", address(0));
        vm.serializeBytes32(objectKey, "timelockCodehash", address(timelock).codehash);
        string memory json = vm.serializeBytes32(objectKey, "routerCodehash", address(router).codehash);
        vm.writeJson(json, string.concat(vm.projectRoot(), "/deployments/4663/operator-fee-router.json"));
    }
}
