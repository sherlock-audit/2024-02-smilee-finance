// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

abstract contract AdminAccess {
    address public Admin;

    /// ERRORS ///

    error CallerNotAdmin();
    error AdminAddressZero();

    /// CONSTRUCTOR ///

    /**
     * @notice Contract constructor
     * @param _admin Admin address
     */
    constructor(address _admin) {
        if (_admin == address(0)) revert AdminAddressZero();
        Admin = _admin;
    }

    /// MODIFIERS

    /**
     * @notice Only admin addresses can call functions that use this modifier
     */
    modifier onlyAdmin() {
        if (msg.sender != Admin) revert CallerNotAdmin();
        _;
    }
}
