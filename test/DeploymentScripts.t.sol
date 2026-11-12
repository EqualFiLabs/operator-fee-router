// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DeployOperatorFeeRouter} from "../script/DeployOperatorFeeRouter.s.sol";
import {BootstrapOperatorFeeRouter} from "../script/BootstrapOperatorFeeRouter.s.sol";
import {OperatorFeeRouter} from "../src/OperatorFeeRouter.sol";
import {OperatorFeeRouterTimelock} from "../src/OperatorFeeRouterTimelock.sol";

/// @dev Keep script tests from overwriting deployment evidence.
contract DeploymentScriptHarness is DeployOperatorFeeRouter {
    function dependencies() external pure returns (address, address, address) {
        return (OPERATOR_COLLECTION, ACTIVATION_REGISTRY, OPERATOR_VAULT);
    }

    function _writeCandidate(OperatorFeeRouterTimelock, OperatorFeeRouter, address[] memory, address[] memory)
        internal
        override
    {}
}

/// @dev Records the script's calls without replacing the production router's own bootstrap tests.
contract BootstrapCallRecorder {
    uint256 public constant LAST_OPERATOR_ID = 5_555;
    uint256 public constant MAX_BOOTSTRAP_BATCH = 100;
    address internal immutable expectedSender;
    uint256 public nextOperatorId;
    bool public bootstrapFinalized;
    uint256 public batches;
    uint256 public finalizations;

    constructor(address sender, uint256 cursor, bool finalized) {
        expectedSender = sender;
        nextOperatorId = cursor;
        bootstrapFinalized = finalized;
    }

    function bootstrapOperators(uint256 count) external returns (uint256 initializedCount, uint256 nextId) {
        require(msg.sender == expectedSender, "unexpected broadcast sender");
        require(count == MAX_BOOTSTRAP_BATCH && !bootstrapFinalized, "invalid bootstrap call");
        uint256 end = nextOperatorId + count;
        if (end > LAST_OPERATOR_ID + 1) end = LAST_OPERATOR_ID + 1;
        initializedCount = end - nextOperatorId;
        nextOperatorId = end;
        ++batches;
        return (initializedCount, end);
    }

    function finalizeBootstrap() external {
        require(msg.sender == expectedSender, "unexpected broadcast sender");
        require(nextOperatorId == LAST_OPERATOR_ID + 1 && !bootstrapFinalized, "incomplete or repeated finalization");
        bootstrapFinalized = true;
        ++finalizations;
    }
}

contract DeploymentScriptsTest is Test {
    DeploymentScriptHarness internal deployment;
    BootstrapOperatorFeeRouter internal bootstrap;
    address internal deployer;
    address internal proposer;

    function setUp() public {
        vm.chainId(4_663);
        deployer = makeAddr("script-deployer");
        proposer = makeAddr("script-proposer");
        vm.setEnv("OPERATOR_ROUTER_DEPLOYER", vm.toString(deployer));
        vm.setEnv("OPERATOR_ROUTER_TIMELOCK_PROPOSER", vm.toString(proposer));
        // A malformed legacy value must never be read by either script.
        vm.setEnv("OPERATOR_ROUTER_DEPLOYER_PRIVATE_KEY", "not-a-private-key");
        deployment = new DeploymentScriptHarness();
        bootstrap = new BootstrapOperatorFeeRouter();
    }

    // Environment cheatcodes are process-wide; keep all mutations in one sequential test.
    function test_PublicSignerDeploymentAndBootstrapScenarios() public {
        _checkDeploymentUsesConfiguredPublicSenderWithoutReadingPrivateKey();
        _checkBootstrapUsesConfiguredPublicSenderForEveryBatch();
        _checkBootstrapResumesAtCurrentCursor();
        _checkBootstrapFinalizesWhenAllOperatorsAreAlreadyInitialized();
        _checkFinalizedBootstrapMakesNoFurtherCalls();
        _checkDeploymentRejectsZeroProposer();
        _checkBothScriptsRejectZeroSender();
        _checkBothScriptsRejectWrongChainBeforeReadingConfiguration();
    }

    function _checkDeploymentUsesConfiguredPublicSenderWithoutReadingPrivateKey() internal {
        (address collection, address registry, address vault) = deployment.dependencies();
        vm.etch(collection, hex"00");
        vm.etch(registry, hex"00");
        vm.etch(vault, hex"00");
        vm.mockCall(collection, abi.encodeWithSignature("COLLECTION_SIZE()"), abi.encode(uint256(5_555)));
        vm.mockCall(collection, abi.encodeWithSignature("vault()"), abi.encode(vault));
        vm.mockCall(collection, abi.encodeWithSignature("activationRegistry()"), abi.encode(registry));
        vm.mockCall(registry, abi.encodeWithSignature("genesisCollection()"), abi.encode(collection));
        uint256 nonce = vm.getNonce(deployer);
        address expectedTimelock = vm.computeCreateAddress(deployer, nonce);
        address expectedRouter = vm.computeCreateAddress(deployer, nonce + 1);

        (OperatorFeeRouterTimelock timelock, OperatorFeeRouter router) = deployment.run();

        assertEq(address(timelock), expectedTimelock);
        assertEq(address(router), expectedRouter);
        assertEq(router.routerTimelock(), address(timelock));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), proposer));
    }

    function _checkBothScriptsRejectWrongChainBeforeReadingConfiguration() internal {
        vm.chainId(1);
        vm.setEnv("OPERATOR_ROUTER_DEPLOYER", "invalid-address");
        vm.expectRevert(abi.encodeWithSelector(DeployOperatorFeeRouter.WrongChain.selector, uint256(1)));
        deployment.run();
        vm.expectRevert(abi.encodeWithSelector(BootstrapOperatorFeeRouter.WrongChain.selector, uint256(1)));
        bootstrap.run();
    }

    function _checkBothScriptsRejectZeroSender() internal {
        _recorder(1, false);
        vm.setEnv("OPERATOR_ROUTER_DEPLOYER", vm.toString(address(0)));
        vm.expectRevert(DeployOperatorFeeRouter.ZeroDeployer.selector);
        deployment.run();
        vm.expectRevert(BootstrapOperatorFeeRouter.ZeroDeployer.selector);
        bootstrap.run();
    }

    function _checkDeploymentRejectsZeroProposer() internal {
        vm.setEnv("OPERATOR_ROUTER_TIMELOCK_PROPOSER", vm.toString(address(0)));
        vm.expectRevert(DeployOperatorFeeRouter.ZeroProposer.selector);
        deployment.run();
    }

    function _checkBootstrapUsesConfiguredPublicSenderForEveryBatch() internal {
        BootstrapCallRecorder recorder = _recorder(1, false);
        bootstrap.run();
        assertEq(recorder.batches(), 56);
        _assertCompleted(recorder);
    }

    function _checkBootstrapResumesAtCurrentCursor() internal {
        BootstrapCallRecorder recorder = _recorder(5_401, false);
        bootstrap.run();
        assertEq(recorder.batches(), 2);
        _assertCompleted(recorder);
    }

    function _checkBootstrapFinalizesWhenAllOperatorsAreAlreadyInitialized() internal {
        BootstrapCallRecorder recorder = _recorder(5_556, false);
        bootstrap.run();
        assertEq(recorder.batches(), 0);
        _assertCompleted(recorder);
    }

    function _checkFinalizedBootstrapMakesNoFurtherCalls() internal {
        BootstrapCallRecorder recorder = _recorder(5_556, true);
        bootstrap.run();
        assertEq(recorder.batches(), 0);
        assertEq(recorder.finalizations(), 0);
    }

    function _recorder(uint256 cursor, bool finalized) internal returns (BootstrapCallRecorder recorder) {
        recorder = new BootstrapCallRecorder(deployer, cursor, finalized);
        vm.setEnv("OPERATOR_FEE_ROUTER", vm.toString(address(recorder)));
    }

    function _assertCompleted(BootstrapCallRecorder recorder) internal view {
        assertEq(recorder.nextOperatorId(), 5_556);
        assertTrue(recorder.bootstrapFinalized());
        assertEq(recorder.finalizations(), 1);
    }
}
