// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";

contract BootstrapOperatorFeeRouter is Script {
    uint256 internal constant ROBINHOOD_CHAIN_ID = 4_663;

    error WrongChain(uint256 actual);

    function run() external {
        if (block.chainid != ROBINHOOD_CHAIN_ID) revert WrongChain(block.chainid);
        OperatorFeeRouter router = OperatorFeeRouter(payable(vm.envAddress("OPERATOR_FEE_ROUTER")));
        uint256 deployerKey = vm.envUint("OPERATOR_ROUTER_DEPLOYER_PRIVATE_KEY");

        if (router.bootstrapFinalized()) return;

        vm.startBroadcast(deployerKey);
        while (router.nextOperatorId() <= router.LAST_OPERATOR_ID()) {
            router.bootstrapOperators(router.MAX_BOOTSTRAP_BATCH());
        }
        router.finalizeBootstrap();
        vm.stopBroadcast();
    }
}
