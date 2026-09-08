// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IActivationRegistry} from "./interfaces/IActivationRegistry.sol";
import {IOperatorCollection} from "./interfaces/IOperatorCollection.sol";
import {LibIndexMath} from "./libraries/LibIndexMath.sol";

/// @notice Standalone, lazy-synchronized reward router for Statics Operator NFTs.
contract OperatorFeeRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant RAY = 1e27;
    uint256 public constant COLLECTION_SIZE = 5_555;
    uint256 public constant FIRST_OPERATOR_ID = 1;
    uint256 public constant LAST_OPERATOR_ID = 5_555;
    uint256 public constant MAX_BOOTSTRAP_BATCH = 100;
    uint256 public constant MAX_REWARD_ASSETS = 64;
    /// @dev Per-asset base-unit bound that leaves more than 1e25 maximum-sized index increments of uint256 headroom.
    uint256 public constant MAX_OUTSTANDING_REWARD_UNITS = type(uint96).max;
    uint16 public constant MIN_MULTIPLIER_BPS = 10_000;
    uint16 public constant MAX_MULTIPLIER_BPS = 12_500;

    enum SyncKind {
        Noop,
        Activation,
        Transfer
    }

    struct OperatorState {
        address syncedOwner;
        uint16 syncedMultiplierBps;
        uint16 effectiveWeight;
        bool initialized;
    }

    struct RewardBook {
        uint256 indexRay;
        uint256 indexRemainder;
        uint256 totalAdded;
        uint256 totalClaimed;
        uint256 accountedLiability;
        uint256 totalForfeited;
        uint256 totalForfeitedRemainderRay;
        bool registered;
        bool depositsEnabled;
    }

    struct OperatorAssetState {
        uint256 checkpointRay;
        uint256 settlementRemainderRay;
        uint256 accrued;
    }

    struct PendingForfeiture {
        uint256 amount;
        uint256 remainderRay;
    }

    IOperatorCollection public immutable operatorCollection;
    IActivationRegistry public immutable activationRegistry;
    address public immutable operatorVault;
    address public immutable routerTimelock;

    uint256 public totalEffectiveWeight;
    uint256 public nextOperatorId = FIRST_OPERATOR_ID;
    bool public bootstrapFinalized;

    mapping(uint256 operatorId => OperatorState state) public operatorState;
    mapping(address asset => RewardBook book) public rewardBook;
    mapping(uint256 operatorId => mapping(address asset => OperatorAssetState state)) public operatorAssetState;
    mapping(uint256 operatorId => mapping(address asset => PendingForfeiture pending)) public pendingForfeiture;

    address[] private _rewardAssets;

    event RewardAssetRegistered(address indexed asset);
    event RewardAssetEnabled(address indexed asset, bool enabled);
    event RewardsAdded(
        address indexed contributor,
        address indexed asset,
        uint256 amount,
        uint256 totalEffectiveWeight,
        uint256 indexRay
    );
    event OperatorInitialized(
        uint256 indexed operatorId,
        address indexed owner,
        uint16 multiplierBps,
        uint16 effectiveWeight,
        uint256 totalEffectiveWeight
    );
    event BootstrapFinalized(uint256 totalEffectiveWeight);
    event OperatorSynced(
        uint256 indexed operatorId,
        address indexed previousOwner,
        address indexed currentOwner,
        uint16 previousMultiplierBps,
        uint16 currentMultiplierBps,
        uint16 previousWeight,
        uint16 currentWeight,
        SyncKind kind
    );
    event OperatorWeightChanged(
        uint256 indexed operatorId, uint16 previousWeight, uint16 currentWeight, uint256 totalEffectiveWeight
    );
    event OperatorRewardsSettled(
        uint256 indexed operatorId,
        address indexed asset,
        uint256 newlyAccrued,
        uint256 totalAccrued,
        uint256 settlementRemainderRay
    );
    event OperatorRewardsForfeited(
        uint256 indexed operatorId, address indexed asset, uint256 amount, uint256 remainderRay
    );
    event ForfeitedRewardsRedistributed(
        uint256 indexed operatorId,
        address indexed asset,
        uint256 amount,
        uint256 remainderRay,
        uint256 denominator,
        uint256 indexRay
    );
    event ForfeitureQueued(
        uint256 indexed operatorId,
        address indexed asset,
        uint256 amount,
        uint256 remainderRay,
        uint256 pendingAmount,
        uint256 pendingRemainderRay
    );
    event PendingForfeitureRedistributed(
        uint256 indexed operatorId,
        address indexed asset,
        uint256 amount,
        uint256 remainderRay,
        uint256 denominator,
        uint256 indexRay
    );
    event RewardIndexCapacityReached(
        uint256 indexed operatorId, address indexed asset, uint256 amount, uint256 remainderRay
    );
    event OperatorRewardsClaimed(
        uint256 indexed operatorId, address indexed owner, address indexed asset, address receiver, uint256 amount
    );
    event SurplusRecovered(address indexed asset, address indexed receiver, uint256 amount);

    error ZeroAddress();
    error AddressHasNoCode(address account);
    error Unauthorized(address caller);
    error InvalidCollectionSize(uint256 actual);
    error InvalidCollectionVault(address expected, address actual);
    error InvalidCollectionRegistry(address expected, address actual);
    error InvalidRegistryCollection(address expected, address actual);
    error InvalidMultiplier(uint16 multiplierBps);
    error InvalidBootstrapCount(uint256 count);
    error BootstrapAlreadyFinalized();
    error BootstrapIncomplete(uint256 nextUninitializedOperatorId);
    error BootstrapNotFinalized();
    error OperatorNotInitialized(uint256 operatorId);
    error RewardAssetAlreadyRegistered(address asset);
    error RewardAssetNotRegistered(address asset);
    error RewardAssetDisabled(address asset);
    error RewardAssetLimitReached();
    error ZeroAmount();
    error ZeroEffectiveWeight();
    error RewardLiabilityLimitExceeded(address asset, uint256 currentLiability, uint256 amount, uint256 limit);
    error RewardIndexCapacityExceeded(address asset);
    error InvalidReceiver(address receiver);
    error InexactTokenTransfer(address asset, uint256 expected, uint256 spent, uint256 received);
    error NotOperatorOwner(uint256 operatorId, address caller, address owner);
    error VaultCannotClaim(uint256 operatorId);
    error NoRewards();
    error NoPendingForfeiture(uint256 operatorId, address asset);
    error NoOtherEffectiveWeight(uint256 operatorId);
    error InsufficientSurplus(address asset, uint256 requested, uint256 available);
    error NativeAssetUnsupported();

    modifier onlyTimelock() {
        if (msg.sender != routerTimelock) revert Unauthorized(msg.sender);
        _;
    }

    constructor(
        address operatorCollection_,
        address activationRegistry_,
        address operatorVault_,
        address routerTimelock_
    ) {
        _requireContract(operatorCollection_);
        _requireContract(activationRegistry_);
        _requireContract(operatorVault_);
        _requireContract(routerTimelock_);

        IOperatorCollection collection = IOperatorCollection(operatorCollection_);
        IActivationRegistry registry = IActivationRegistry(activationRegistry_);
        uint256 collectionSize = collection.COLLECTION_SIZE();
        if (collectionSize != COLLECTION_SIZE) revert InvalidCollectionSize(collectionSize);

        address configuredVault = collection.vault();
        if (configuredVault != operatorVault_) revert InvalidCollectionVault(operatorVault_, configuredVault);
        address configuredRegistry = collection.activationRegistry();
        if (configuredRegistry != activationRegistry_) {
            revert InvalidCollectionRegistry(activationRegistry_, configuredRegistry);
        }
        address configuredCollection = registry.genesisCollection();
        if (configuredCollection != operatorCollection_) {
            revert InvalidRegistryCollection(operatorCollection_, configuredCollection);
        }

        operatorCollection = collection;
        activationRegistry = registry;
        operatorVault = operatorVault_;
        routerTimelock = routerTimelock_;
    }

    receive() external payable {
        revert NativeAssetUnsupported();
    }

    function bootstrapOperators(uint256 maxCount) external returns (uint256 initializedCount, uint256 nextId) {
        if (bootstrapFinalized) revert BootstrapAlreadyFinalized();
        if (maxCount == 0 || maxCount > MAX_BOOTSTRAP_BATCH) revert InvalidBootstrapCount(maxCount);

        uint256 cursor = nextOperatorId;
        uint256 exclusiveEnd = cursor + maxCount;
        uint256 collectionEnd = LAST_OPERATOR_ID + 1;
        if (exclusiveEnd > collectionEnd) exclusiveEnd = collectionEnd;

        uint256 assetCount = _rewardAssets.length;
        for (uint256 operatorId = cursor; operatorId < exclusiveEnd; ++operatorId) {
            (address owner, uint16 multiplierBps) = _readCanonical(operatorId);
            uint16 weight = owner == operatorVault ? 0 : multiplierBps;
            operatorState[operatorId] = OperatorState(owner, multiplierBps, weight, true);
            totalEffectiveWeight += weight;

            for (uint256 i; i < assetCount; ++i) {
                address asset = _rewardAssets[i];
                operatorAssetState[operatorId][asset].checkpointRay = rewardBook[asset].indexRay;
            }

            emit OperatorInitialized(operatorId, owner, multiplierBps, weight, totalEffectiveWeight);
            ++initializedCount;
        }

        nextOperatorId = exclusiveEnd;
        nextId = exclusiveEnd;
    }

    function finalizeBootstrap() external {
        if (bootstrapFinalized) revert BootstrapAlreadyFinalized();
        if (nextOperatorId != LAST_OPERATOR_ID + 1) revert BootstrapIncomplete(nextOperatorId);
        bootstrapFinalized = true;
        emit BootstrapFinalized(totalEffectiveWeight);
    }

    function registerRewardAsset(address asset) external onlyTimelock {
        _requireContract(asset);
        RewardBook storage book = rewardBook[asset];
        if (book.registered) revert RewardAssetAlreadyRegistered(asset);
        if (_rewardAssets.length == MAX_REWARD_ASSETS) revert RewardAssetLimitReached();

        book.registered = true;
        book.depositsEnabled = true;
        _rewardAssets.push(asset);
        emit RewardAssetRegistered(asset);
        emit RewardAssetEnabled(asset, true);
    }

    function setRewardAssetEnabled(address asset, bool enabled) external onlyTimelock {
        RewardBook storage book = _registeredRewardBook(asset);
        if (book.depositsEnabled == enabled) return;
        book.depositsEnabled = enabled;
        emit RewardAssetEnabled(asset, enabled);
    }

    function addRewards(address asset, uint256 amount) external nonReentrant {
        if (!bootstrapFinalized) revert BootstrapNotFinalized();
        RewardBook storage book = _registeredRewardBook(asset);
        if (!book.depositsEnabled) revert RewardAssetDisabled(asset);
        if (amount == 0) revert ZeroAmount();
        uint256 liability = book.accountedLiability;
        if (amount > MAX_OUTSTANDING_REWARD_UNITS - liability) {
            revert RewardLiabilityLimitExceeded(asset, liability, amount, MAX_OUTSTANDING_REWARD_UNITS);
        }
        uint256 denominator = totalEffectiveWeight;
        if (denominator == 0) revert ZeroEffectiveWeight();

        IERC20 token = IERC20(asset);
        uint256 senderBefore = token.balanceOf(msg.sender);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 senderAfter = token.balanceOf(msg.sender);
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 spent = senderBefore >= senderAfter ? senderBefore - senderAfter : 0;
        uint256 received = balanceAfter >= balanceBefore ? balanceAfter - balanceBefore : 0;
        if (spent != amount || received != amount) revert InexactTokenTransfer(asset, amount, spent, received);

        _increaseIndex(asset, book, amount, 0, denominator);
        book.totalAdded += amount;
        book.accountedLiability += amount;
        emit RewardsAdded(msg.sender, asset, amount, denominator, book.indexRay);
    }

    function syncOperator(uint256 operatorId) external nonReentrant returns (SyncKind kind) {
        _requireInitialized(operatorId);
        kind = _syncOperator(operatorId);
    }

    function flushPendingForfeiture(uint256 operatorId, address asset)
        external
        nonReentrant
        returns (uint256 amount, uint256 remainderRay)
    {
        OperatorState storage state = _requireInitialized(operatorId);
        RewardBook storage book = _registeredRewardBook(asset);
        PendingForfeiture storage pending = pendingForfeiture[operatorId][asset];
        amount = pending.amount;
        remainderRay = pending.remainderRay;
        if (amount == 0 && remainderRay == 0) revert NoPendingForfeiture(operatorId, asset);

        uint256 denominator = totalEffectiveWeight - state.effectiveWeight;
        if (denominator == 0) revert NoOtherEffectiveWeight(operatorId);

        _settle(operatorId, asset, state.effectiveWeight, book);
        pending.amount = 0;
        pending.remainderRay = 0;
        _increaseIndex(asset, book, amount, remainderRay, denominator);
        operatorAssetState[operatorId][asset].checkpointRay = book.indexRay;

        emit PendingForfeitureRedistributed(operatorId, asset, amount, remainderRay, denominator, book.indexRay);
    }

    function claimOperatorRewards(uint256 operatorId, address asset, address receiver)
        external
        nonReentrant
        returns (uint256 amount)
    {
        _validateReceiver(receiver);
        RewardBook storage book = _registeredRewardBook(asset);
        OperatorState storage state = _requireInitialized(operatorId);
        SyncKind syncKind = _syncOperator(operatorId);

        address owner = state.syncedOwner;
        if (msg.sender != owner) revert NotOperatorOwner(operatorId, msg.sender, owner);
        if (owner == operatorVault) revert VaultCannotClaim(operatorId);

        _settle(operatorId, asset, state.effectiveWeight, book);
        OperatorAssetState storage assetState = operatorAssetState[operatorId][asset];
        amount = assetState.accrued;
        if (amount == 0) {
            if (syncKind == SyncKind.Noop) revert NoRewards();
            return 0;
        }

        assetState.accrued = 0;
        book.totalClaimed += amount;
        book.accountedLiability -= amount;
        _pushExact(asset, receiver, amount);
        emit OperatorRewardsClaimed(operatorId, owner, asset, receiver, amount);
    }

    function recoverSurplus(address asset, address receiver, uint256 amount) external onlyTimelock nonReentrant {
        _requireContract(asset);
        _validateReceiver(receiver);
        if (amount == 0) revert ZeroAmount();

        uint256 balance = IERC20(asset).balanceOf(address(this));
        uint256 liability = rewardBook[asset].accountedLiability;
        uint256 surplus = balance > liability ? balance - liability : 0;
        if (amount > surplus) revert InsufficientSurplus(asset, amount, surplus);

        _pushExact(asset, receiver, amount);
        emit SurplusRecovered(asset, receiver, amount);
    }

    function pendingOperatorRewards(uint256 operatorId, address asset) external view returns (uint256 amount) {
        OperatorState storage state = operatorState[operatorId];
        if (!state.initialized) revert OperatorNotInitialized(operatorId);
        RewardBook storage book = rewardBook[asset];
        if (!book.registered) revert RewardAssetNotRegistered(asset);

        (address currentOwner, uint16 currentMultiplierBps) = _readCanonical(operatorId);
        if (currentOwner != state.syncedOwner || currentMultiplierBps < state.syncedMultiplierBps) return 0;

        OperatorAssetState storage assetState = operatorAssetState[operatorId][asset];
        amount = assetState.accrued;
        uint256 indexDeltaRay = book.indexRay - assetState.checkpointRay;
        if (indexDeltaRay == 0 || state.effectiveWeight == 0) return amount;

        amount += Math.mulDiv(state.effectiveWeight, indexDeltaRay, RAY);
        uint256 remainderRay = mulmod(state.effectiveWeight, indexDeltaRay, RAY);
        if (remainderRay >= RAY - assetState.settlementRemainderRay) ++amount;
    }

    function effectiveWeight(uint256 operatorId) external view returns (uint256 weight) {
        weight = operatorState[operatorId].effectiveWeight;
    }

    function syncedOwner(uint256 operatorId) external view returns (address owner) {
        owner = operatorState[operatorId].syncedOwner;
    }

    function syncedMultiplierBps(uint256 operatorId) external view returns (uint16 multiplierBps) {
        multiplierBps = operatorState[operatorId].syncedMultiplierBps;
    }

    function isRewardAsset(address asset) external view returns (bool) {
        return rewardBook[asset].registered;
    }

    function rewardAssetEnabled(address asset) external view returns (bool) {
        return rewardBook[asset].depositsEnabled;
    }

    function rewardAssetCount() external view returns (uint256) {
        return _rewardAssets.length;
    }

    function rewardAssetAt(uint256 index) external view returns (address) {
        return _rewardAssets[index];
    }

    function availableSurplus(address asset) external view returns (uint256) {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        uint256 liability = rewardBook[asset].accountedLiability;
        return balance > liability ? balance - liability : 0;
    }

    function _syncOperator(uint256 operatorId) internal returns (SyncKind kind) {
        OperatorState storage state = operatorState[operatorId];
        (address currentOwner, uint16 currentMultiplierBps) = _readCanonical(operatorId);
        address previousOwner = state.syncedOwner;
        uint16 previousMultiplierBps = state.syncedMultiplierBps;
        uint16 previousWeight = state.effectiveWeight;

        if (currentOwner == previousOwner && currentMultiplierBps == previousMultiplierBps) {
            kind = SyncKind.Noop;
            emit OperatorSynced(
                operatorId,
                previousOwner,
                currentOwner,
                previousMultiplierBps,
                currentMultiplierBps,
                previousWeight,
                previousWeight,
                kind
            );
            return kind;
        }

        uint16 currentWeight = currentOwner == operatorVault ? 0 : currentMultiplierBps;
        if (currentOwner == previousOwner && currentMultiplierBps > previousMultiplierBps) {
            _settleAll(operatorId, previousWeight);
            totalEffectiveWeight = totalEffectiveWeight - previousWeight + currentWeight;
            state.syncedMultiplierBps = currentMultiplierBps;
            state.effectiveWeight = currentWeight;
            kind = SyncKind.Activation;
        } else {
            _forfeitAndRedistribute(operatorId, previousWeight);
            state.syncedOwner = currentOwner;
            state.syncedMultiplierBps = currentMultiplierBps;
            state.effectiveWeight = currentWeight;
            totalEffectiveWeight += currentWeight;
            kind = SyncKind.Transfer;
        }

        if (currentWeight != previousWeight) {
            emit OperatorWeightChanged(operatorId, previousWeight, currentWeight, totalEffectiveWeight);
        }

        emit OperatorSynced(
            operatorId,
            previousOwner,
            currentOwner,
            previousMultiplierBps,
            currentMultiplierBps,
            previousWeight,
            currentWeight,
            kind
        );
    }

    function _forfeitAndRedistribute(uint256 operatorId, uint16 previousWeight) internal {
        totalEffectiveWeight -= previousWeight;
        uint256 denominator = totalEffectiveWeight;
        uint256 assetCount = _rewardAssets.length;

        for (uint256 i; i < assetCount; ++i) {
            address asset = _rewardAssets[i];
            RewardBook storage book = rewardBook[asset];
            _settle(operatorId, asset, previousWeight, book);

            OperatorAssetState storage assetState = operatorAssetState[operatorId][asset];
            uint256 forfeited = assetState.accrued;
            uint256 forfeitedRemainderRay = assetState.settlementRemainderRay;
            assetState.accrued = 0;
            assetState.settlementRemainderRay = 0;

            if (forfeited != 0 || forfeitedRemainderRay != 0) {
                _recordForfeiture(book, forfeited, forfeitedRemainderRay);
                emit OperatorRewardsForfeited(operatorId, asset, forfeited, forfeitedRemainderRay);

                if (denominator == 0) {
                    _queueForfeiture(operatorId, asset, forfeited, forfeitedRemainderRay);
                } else {
                    bool redistributed = _tryIncreaseIndex(book, forfeited, forfeitedRemainderRay, denominator);
                    if (redistributed) {
                        emit ForfeitedRewardsRedistributed(
                            operatorId, asset, forfeited, forfeitedRemainderRay, denominator, book.indexRay
                        );
                    } else {
                        _queueForfeiture(operatorId, asset, forfeited, forfeitedRemainderRay);
                        emit RewardIndexCapacityReached(operatorId, asset, forfeited, forfeitedRemainderRay);
                    }
                }
            }

            assetState.checkpointRay = book.indexRay;
        }
    }

    function _settleAll(uint256 operatorId, uint16 weight) internal {
        uint256 assetCount = _rewardAssets.length;
        for (uint256 i; i < assetCount; ++i) {
            address asset = _rewardAssets[i];
            _settle(operatorId, asset, weight, rewardBook[asset]);
        }
    }

    function _settle(uint256 operatorId, address asset, uint16 weight, RewardBook storage book) internal {
        OperatorAssetState storage assetState = operatorAssetState[operatorId][asset];
        uint256 indexRay = book.indexRay;
        uint256 indexDeltaRay = indexRay - assetState.checkpointRay;
        if (indexDeltaRay == 0) return;

        assetState.checkpointRay = indexRay;
        if (weight == 0) return;

        uint256 newlyAccrued = Math.mulDiv(weight, indexDeltaRay, RAY);
        uint256 remainderRay = mulmod(weight, indexDeltaRay, RAY);
        uint256 priorRemainderRay = assetState.settlementRemainderRay;
        if (remainderRay >= RAY - priorRemainderRay) {
            ++newlyAccrued;
            remainderRay -= RAY - priorRemainderRay;
        } else {
            remainderRay += priorRemainderRay;
        }

        assetState.accrued += newlyAccrued;
        assetState.settlementRemainderRay = remainderRay;
        emit OperatorRewardsSettled(operatorId, asset, newlyAccrued, assetState.accrued, remainderRay);
    }

    function _increaseIndex(
        address asset,
        RewardBook storage book,
        uint256 amount,
        uint256 scaledRemainderRay,
        uint256 denominator
    ) internal {
        if (!_tryIncreaseIndex(book, amount, scaledRemainderRay, denominator)) {
            revert RewardIndexCapacityExceeded(asset);
        }
    }

    function _tryIncreaseIndex(RewardBook storage book, uint256 amount, uint256 scaledRemainderRay, uint256 denominator)
        internal
        returns (bool increased)
    {
        if (amount > MAX_OUTSTANDING_REWARD_UNITS || scaledRemainderRay >= RAY) return false;
        (uint256 delta, uint256 remainder) =
            LibIndexMath.indexDelta(amount, scaledRemainderRay, denominator, book.indexRemainder);
        if (delta > type(uint256).max - book.indexRay) return false;
        book.indexRay += delta;
        book.indexRemainder = remainder;
        increased = true;
    }

    function _recordForfeiture(RewardBook storage book, uint256 amount, uint256 remainderRay) internal {
        book.totalForfeited += amount;
        uint256 combinedRemainderRay = book.totalForfeitedRemainderRay + remainderRay;
        if (combinedRemainderRay >= RAY) {
            ++book.totalForfeited;
            combinedRemainderRay -= RAY;
        }
        book.totalForfeitedRemainderRay = combinedRemainderRay;
    }

    function _queueForfeiture(uint256 operatorId, address asset, uint256 amount, uint256 remainderRay) internal {
        PendingForfeiture storage pending = pendingForfeiture[operatorId][asset];
        pending.amount += amount;
        uint256 combinedRemainderRay = pending.remainderRay + remainderRay;
        if (combinedRemainderRay >= RAY) {
            ++pending.amount;
            combinedRemainderRay -= RAY;
        }
        pending.remainderRay = combinedRemainderRay;
        emit ForfeitureQueued(operatorId, asset, amount, remainderRay, pending.amount, pending.remainderRay);
    }

    function _readCanonical(uint256 operatorId) internal view returns (address owner, uint16 multiplierBps) {
        owner = operatorCollection.ownerOf(operatorId);
        multiplierBps = activationRegistry.multiplierBps(operatorId);
        if (multiplierBps < MIN_MULTIPLIER_BPS || multiplierBps > MAX_MULTIPLIER_BPS) {
            revert InvalidMultiplier(multiplierBps);
        }
    }

    function _registeredRewardBook(address asset) internal view returns (RewardBook storage book) {
        book = rewardBook[asset];
        if (!book.registered) revert RewardAssetNotRegistered(asset);
    }

    function _requireInitialized(uint256 operatorId) internal view returns (OperatorState storage state) {
        state = operatorState[operatorId];
        if (!state.initialized) revert OperatorNotInitialized(operatorId);
    }

    function _pushExact(address asset, address receiver, uint256 amount) internal {
        IERC20 token = IERC20(asset);
        uint256 senderBefore = token.balanceOf(address(this));
        uint256 receiverBefore = token.balanceOf(receiver);
        token.safeTransfer(receiver, amount);
        uint256 senderAfter = token.balanceOf(address(this));
        uint256 receiverAfter = token.balanceOf(receiver);
        uint256 spent = senderBefore >= senderAfter ? senderBefore - senderAfter : 0;
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (spent != amount || received != amount) {
            revert InexactTokenTransfer(asset, amount, spent, received);
        }
    }

    function _validateReceiver(address receiver) internal view {
        if (receiver == address(0) || receiver == address(this)) revert InvalidReceiver(receiver);
    }

    function _requireContract(address account) internal view {
        if (account == address(0)) revert ZeroAddress();
        if (account.code.length == 0) revert AddressHasNoCode(account);
    }
}
