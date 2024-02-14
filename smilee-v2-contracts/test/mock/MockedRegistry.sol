// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Registry} from "../../src/periphery/Registry.sol";

contract MockedRegistry is Registry {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => bool) internal _registeredDvps;

    function registerDVP(address addr) external onlyRole(ROLE_ADMIN) {
        _registeredDvps[addr] = true;
    }

    function registerVault(address addr) external onlyRole(ROLE_ADMIN) {
        _registeredVaults[addr] = true;
    }

    function isRegistered(address dvp) public view virtual override returns (bool registered) {
        return super.isRegistered(dvp) || _registeredDvps[dvp];
    }

    function unregister(address dvp) public virtual override {
        if (_dvps.contains(dvp)) {
            super.unregister(dvp);
        } else {
            if (!_registeredDvps[dvp]) {
                revert MissingAddress();
            }
        }
        _registeredDvps[dvp] = false;
    }

}
