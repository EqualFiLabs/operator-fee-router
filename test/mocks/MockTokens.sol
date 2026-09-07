// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract MockFeeToken is MockERC20 {
    bool public feeEnabled;

    constructor() MockERC20("Fee Token", "FEE") {}

    function setFeeEnabled(bool enabled) external {
        feeEnabled = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (feeEnabled && from != address(0) && to != address(0) && value != 0) {
            uint256 fee = value / 10;
            if (fee == 0) fee = 1;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
        } else {
            super._update(from, to, value);
        }
    }
}

contract MockSenderFeeToken is MockERC20 {
    bool public feeEnabled;

    constructor() MockERC20("Sender Fee Token", "SENDERFEE") {}

    function setFeeEnabled(bool enabled) external {
        feeEnabled = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (feeEnabled && from != address(0) && to != address(0) && value != 0) {
            uint256 fee = value / 10;
            if (fee == 0) fee = 1;
            super._update(from, address(0), fee);
            super._update(from, to, value);
        } else {
            super._update(from, to, value);
        }
    }
}

contract MockReentrantToken is MockERC20 {
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackAttempted;
    bool public callbackSucceeded;

    constructor() MockERC20("Reentrant Token", "REENT") {}

    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        bool result = super.transferFrom(from, to, value);
        if (callbackTarget != address(0)) {
            callbackAttempted = true;
            (callbackSucceeded,) = callbackTarget.call(callbackData);
        }
        return result;
    }
}
