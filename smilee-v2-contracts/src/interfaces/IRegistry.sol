// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IRegistry {
    /**
     * Registers an address as DVP into the registry
     * @param dvp A DVP address to register
     */
    function register(address dvp) external;

    /**
     * @notice Checks wheather an address is a known DVP or not
     * @param dvp A supposed DVP address
     * @return registered True if it is a known DVP
     */
    function isRegistered(address dvp) external view returns (bool registered);

    /**
     * @notice Checks wheather an address is a known Vault or not
     * @param vault A supposed Vault address
     * @return registered True if it is a known Vault
     */
    function isRegisteredVault(address vault) external view returns (bool registered);

    /**
     * Unregister an address from the registry
     * @param addr A generic address to remove
     */
    function unregister(address addr) external;

    /**
     * Get DVPs to roll
     * @return list The DVPs to roll
     * @return number The number of DVPs to roll
     */
    function getUnrolledDVPs() external view returns (address[] memory list, uint256 number);

    /**
     * Get all sideTokens used by at least one DVP
     * @return sideTokens The sideTokens list
     */
    function getSideTokens() external view returns (address[] memory sideTokens);
}
