// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IDVP} from "../interfaces/IDVP.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {Epoch, EpochController} from "../lib/EpochController.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Registry is AccessControl, IRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EpochController for Epoch;

    EnumerableSet.AddressSet internal _dvps;
    EnumerableSet.AddressSet internal _baseTokens;
    EnumerableSet.AddressSet internal _sideTokens;

    mapping(address => bool) internal _registeredVaults;
    mapping(address => EnumerableSet.AddressSet) internal _dvpsBySideToken;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    event Registered(address dvp);
    event Unregistered(address dvp);

    error MissingAddress();

    constructor() AccessControl() {
        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    /// @inheritdoc IRegistry
    function register(address dvp) public virtual onlyRole(ROLE_ADMIN) {
        if (_dvps.contains(dvp)) {
            return;
        }

        _dvps.add(dvp);

        _registeredVaults[IDVP(dvp).vault()] = true;

        address baseToken = IDVP(dvp).baseToken();
        _baseTokens.add(baseToken);

        address sideToken = IDVP(dvp).sideToken();
        _sideTokens.add(sideToken);
        _dvpsBySideToken[sideToken].add(dvp);

        emit Registered(dvp);
    }

    /// @inheritdoc IRegistry
    function isRegistered(address dvp) public view virtual returns (bool registered) {
        registered = _dvps.contains(dvp);
    }

    /// @inheritdoc IRegistry
    function isRegisteredVault(address vault) external view override returns (bool registered) {
        registered = _registeredVaults[vault];
    }

    /// @inheritdoc IRegistry
    function unregister(address addr) public virtual onlyRole(ROLE_ADMIN) {
        if (!_dvps.contains(addr)) {
            revert MissingAddress();
        }

        delete _registeredVaults[IDVP(addr).vault()];

        _dvps.remove(addr);

        address sideToken = IDVP(addr).sideToken();
        _dvpsBySideToken[sideToken].remove(addr);
        if (_dvpsBySideToken[sideToken].length() == 0) {
            _sideTokens.remove(sideToken);
        }

        emit Unregistered(addr);
    }

    /// @inheritdoc IRegistry
    function getUnrolledDVPs() external view returns (address[] memory list, uint256 number) {
        uint256 tot = _dvps.length();
        list = new address[](tot);

        for (uint256 i = 0; i < tot; i++) {
            address dvpAddr = _dvps.at(i);

            IDVP dvp = IDVP(dvpAddr);
            Epoch memory epoch = dvp.getEpoch();
            if (epoch.timeToNextEpoch() != 0 || Pausable(dvpAddr).paused()) {
                continue;
            }

            list[number] = dvpAddr;
            number++;
        }
    }

    function getBaseTokens() external view returns (address[] memory) {
        return _baseTokens.values();
    }

    function getSideTokens() external view returns (address[] memory) {
        return _sideTokens.values();
    }

    function getDvpsBySideToken(address sideToken) external view returns (address[] memory) {
        return _dvpsBySideToken[sideToken].values();
    }

    function getDVPs() external view returns (address[] memory) {
        return _dvps.values();
    }
}
