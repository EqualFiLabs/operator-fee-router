// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {OperatorFeeRouter} from "../../src/OperatorFeeRouter.sol";
import {IOperatorCollection} from "../../src/interfaces/IOperatorCollection.sol";
import {IActivationRegistry} from "../../src/interfaces/IActivationRegistry.sol";
import {MockERC20} from "../mocks/MockTokens.sol";

interface ILockView {
    function locked(uint256 id) external view returns (bool);
}

/// @dev Read-only observer. Never installed in the production router or canonical contracts.
contract RehearsalProbe {
    struct Totals {
        uint256 weight;
        uint256 scaled;
        uint256 initialized;
        uint256 mismatches;
    }

    function scan(OperatorFeeRouter router, address asset, uint256 start, uint256 count, bool canonical)
        external
        view
        returns (Totals memory result)
    {
        (uint256 index,,,,,,,,) = router.rewardBook(asset);
        for (uint256 id = start; id < start + count; ++id) {
            (address owner, uint16 multiplier, uint16 w, bool ready) = router.operatorState(id);
            result.scaled += _scaled(router, asset, id, index, w);
            result.weight += w;
            if (ready) ++result.initialized;
            if (canonical && !_canonical(router, id, owner, multiplier, w)) ++result.mismatches;
        }
    }

    function _scaled(OperatorFeeRouter router, address asset, uint256 id, uint256 index, uint256 weight)
        private
        view
        returns (uint256)
    {
        (uint256 checkpoint, uint256 remainder, uint256 accrued) = router.operatorAssetState(id, asset);
        (uint256 pending, uint256 pendingRemainder) = router.pendingForfeiture(id, asset);
        require(checkpoint <= index && remainder < 1e27 && pendingRemainder < 1e27, "normalization");
        return (accrued + pending) * 1e27 + remainder + pendingRemainder + weight * (index - checkpoint);
    }

    function _canonical(OperatorFeeRouter router, uint256 id, address owner, uint16 multiplier, uint16 weight)
        private
        view
        returns (bool)
    {
        address actualOwner = router.operatorCollection().ownerOf(id);
        uint16 actualMultiplier = router.activationRegistry().multiplierBps(id);
        uint16 actualWeight = actualOwner == router.operatorVault() ? 0 : actualMultiplier;
        return owner == actualOwner && multiplier == actualMultiplier && weight == actualWeight;
    }

    function candidate(address collection, address registry, address vault, uint256 start, uint256 count)
        external
        view
        returns (uint256 id, address owner, uint256 multiplier)
    {
        for (uint256 i = start; i < start + count; ++i) {
            address o = IOperatorCollection(collection).ownerOf(i);
            if (o != vault && !ILockView(collection).locked(i)) {
                return (i, o, IActivationRegistry(registry).multiplierBps(i));
            }
        }
    }
}

/// @dev Synthetic adversarial asset, deliberately separate from mainnet assets.
contract RehearsalToken is MockERC20 {
    uint8 private immutable _decimals;
    bool public blocked;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackAttempted;
    bool public callbackSucceeded;

    constructor(uint8 decimals_) MockERC20("Rehearsal asset", "RHR") {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setBlocked(bool value) external {
        blocked = value;
    }

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
        callbackAttempted = false;
        callbackSucceeded = false;
    }

    function _update(address from, address to, uint256 amount) internal override {
        require(!blocked || from == address(0), "blocked");
        super._update(from, to, amount);
        if (from != address(0) && callbackTarget != address(0)) {
            callbackAttempted = true;
            (callbackSucceeded,) = callbackTarget.call(callbackData);
        }
    }
}

contract RehearsalFalseToken is MockERC20 {
    bool public falseReturn;
    constructor() MockERC20("False return fixture", "FALSE") {}

    function setFalseReturn(bool value) external {
        falseReturn = value;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        return !falseReturn;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        return !falseReturn;
    }
}
