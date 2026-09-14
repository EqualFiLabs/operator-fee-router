// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {OperatorFeeRouter} from "../../src/OperatorFeeRouter.sol";

/// @notice Minimal exact-transfer token used only as a linked Certora dependency.
/// @dev Authorization is intentionally omitted: the router proofs constrain successful exact movement, while
///      allowance behavior belongs to each governance-approved reward token.
abstract contract FormalExactToken {
    mapping(address account => uint256 amount) public balanceOf;

    function mint(address receiver, uint256 amount) external {
        balanceOf[receiver] += amount;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address receiver, uint256 amount) external returns (bool) {
        _transfer(msg.sender, receiver, amount);
        return true;
    }

    function transferFrom(address sender, address receiver, uint256 amount) external returns (bool) {
        _transfer(sender, receiver, amount);
        return true;
    }

    function _transfer(address sender, address receiver, uint256 amount) internal {
        uint256 senderBalance = balanceOf[sender];
        require(senderBalance >= amount, "insufficient balance");
        if (sender == receiver) return;
        balanceOf[sender] = senderBalance - amount;
        balanceOf[receiver] += amount;
    }
}

contract FormalRewardTokenA is FormalExactToken {}

contract FormalRewardTokenB is FormalExactToken {}

/// @notice One linked contract supplies every immutable canonical dependency used by the bounded proof scene.
contract FormalOperatorSystem {
    uint256 public constant COLLECTION_SIZE = 5_555;
    address public immutable vault;
    address public immutable activationRegistry;
    address public immutable genesisCollection;

    mapping(uint256 operatorId => address owner) internal _ownerOf;
    mapping(uint256 operatorId => uint16 multiplier) internal _multiplierBps;

    constructor() {
        vault = address(this);
        activationRegistry = address(this);
        genesisCollection = address(this);
        _ownerOf[1] = address(0x1111);
        _ownerOf[2] = address(0x2222);
        _ownerOf[3] = address(this);
        _multiplierBps[1] = 10_000;
        _multiplierBps[2] = 10_000;
        _multiplierBps[3] = 10_000;
    }

    function ownerOf(uint256 operatorId) external view returns (address) {
        return _ownerOf[operatorId];
    }

    function multiplierBps(uint256 operatorId) external view returns (uint16) {
        return _multiplierBps[operatorId];
    }

    function setCanonical(uint256 operatorId, address owner, uint16 multiplier) external {
        _ownerOf[operatorId] = owner;
        _multiplierBps[operatorId] = multiplier;
    }
}

/// @notice Production-router inheritance harness with a three-Operator/two-asset bounded initial scene.
/// @dev The only substituted behavior is bootstrap sizing. All reward, settlement, sync, forfeiture, and claim logic
///      executes the production OperatorFeeRouter implementation.
contract OperatorFeeRouterCertoraHarness is OperatorFeeRouter {
    address public immutable rewardA;
    address public immutable rewardB;

    constructor(address system, address rewardA_, address rewardB_)
        OperatorFeeRouter(system, system, system, system)
    {
        rewardA = rewardA_;
        rewardB = rewardB_;

        for (uint256 operatorId = 1; operatorId <= 3; ++operatorId) {
            (address owner, uint16 multiplier) = _readCanonical(operatorId);
            uint16 weight = owner == operatorVault ? 0 : multiplier;
            operatorState[operatorId] = OperatorState(owner, multiplier, weight, true);
            totalEffectiveWeight += weight;
        }
        nextOperatorId = LAST_OPERATOR_ID + 1;
        bootstrapFinalized = true;
    }

    function formalOperatorInitialized(uint256 operatorId) external view returns (bool) {
        return operatorState[operatorId].initialized;
    }

    function formalBookIndex(address asset) external view returns (uint256) {
        return rewardBook[asset].indexRay;
    }

    function formalBookIndexRemainder(address asset) external view returns (uint256) {
        return rewardBook[asset].indexRemainder;
    }

    function formalBookTotalAdded(address asset) external view returns (uint256) {
        return rewardBook[asset].totalAdded;
    }

    function formalBookTotalClaimed(address asset) external view returns (uint256) {
        return rewardBook[asset].totalClaimed;
    }

    function formalBookLiability(address asset) external view returns (uint256) {
        return rewardBook[asset].accountedLiability;
    }

    function formalBookTotalForfeited(address asset) external view returns (uint256) {
        return rewardBook[asset].totalForfeited;
    }

    function formalBookForfeitedRemainder(address asset) external view returns (uint256) {
        return rewardBook[asset].totalForfeitedRemainderRay;
    }

    function formalCheckpoint(uint256 operatorId, address asset) external view returns (uint256) {
        return operatorAssetState[operatorId][asset].checkpointRay;
    }

    function formalSettlementRemainder(uint256 operatorId, address asset) external view returns (uint256) {
        return operatorAssetState[operatorId][asset].settlementRemainderRay;
    }

    function formalAccrued(uint256 operatorId, address asset) external view returns (uint256) {
        return operatorAssetState[operatorId][asset].accrued;
    }

    function formalPendingForfeitureAmount(uint256 operatorId, address asset) external view returns (uint256) {
        return pendingForfeiture[operatorId][asset].amount;
    }

    function formalPendingForfeitureRemainder(uint256 operatorId, address asset) external view returns (uint256) {
        return pendingForfeiture[operatorId][asset].remainderRay;
    }

    function formalStoredWeightSum() external view returns (uint256 sum) {
        for (uint256 operatorId = 1; operatorId <= 3; ++operatorId) {
            sum += operatorState[operatorId].effectiveWeight;
        }
    }
}
