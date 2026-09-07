// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

contract MockVault {}

contract MockAuthority {}

contract MockOperatorCollection {
    uint256 public constant COLLECTION_SIZE = 5_555;

    address public immutable vault;
    address public activationRegistry;
    mapping(uint256 operatorId => address owner) private _ownerOf;

    constructor(address vault_) {
        vault = vault_;
    }

    function bindActivationRegistry(address registry) external {
        require(activationRegistry == address(0), "already bound");
        activationRegistry = registry;
    }

    function ownerOf(uint256 operatorId) external view returns (address) {
        require(operatorId >= 1 && operatorId <= COLLECTION_SIZE, "invalid operator");
        address owner = _ownerOf[operatorId];
        return owner == address(0) ? vault : owner;
    }

    function setOwner(uint256 operatorId, address owner) external {
        require(operatorId >= 1 && operatorId <= COLLECTION_SIZE, "invalid operator");
        _ownerOf[operatorId] = owner;
    }
}

contract MockActivationRegistry {
    address public immutable genesisCollection;
    mapping(uint256 operatorId => uint16 multiplier) private _multiplierBps;

    constructor(address collection) {
        genesisCollection = collection;
    }

    function multiplierBps(uint256 operatorId) external view returns (uint16) {
        uint16 multiplier = _multiplierBps[operatorId];
        return multiplier == 0 ? 10_000 : multiplier;
    }

    function setMultiplier(uint256 operatorId, uint16 multiplier) external {
        _multiplierBps[operatorId] = multiplier;
    }
}
