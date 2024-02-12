// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IRewarder} from "./IRewarder.sol";

interface IMasterChefSmilee {
    /**
        @notice Allows adding a new vault to the list of supported vaults for staking.
        @param _vault The address of the vault where the shares will be staked.
        @param _allocPoint The weight of the vault in the reward allocation calculation
        @param _rewarder Address of the rewarder delegate.
        @dev Can only be called by the owner
             Vault can't be added twice
     */
    function add(address _vault, uint256 _allocPoint, IRewarder _rewarder) external;

    /**
        @notice Allows to update allocation point for a single vault.
        @param _vault The address of the vault where the shares will be staked.
        @param _allocPoint The weight of the vault in the reward allocation calculation
        @param _rewarder Address of the rewarder delegate.
        @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
        @dev Can only be called by the owner
     */
    function set(address _vault, uint256 _allocPoint, IRewarder _rewarder, bool overwrite) external;

    /**
        @notice Allows staking a specified amount of shares in the provided vault.
        @param _vault The address of the vault where the shares will be staked.
        @param _amount The amount of shares to be deposited in the vault.
        @dev Transfers a specified amount of shares to the indicated vault within the contract.
     */
    function deposit(address _vault, uint256 _amount) external;

    /**
        @notice Allows withdrawing a specified amount of shares from the provided vault.
                Additionally, it triggers the harvesting of rewards associated with the withdrawn shares.
        @param _vault The address of the vault from which shares will be withdrawn.
        @param _amount The amount of shares to be withdrawn from the vault.
        @dev Withdraws a specified amount of shares from the indicated vault and harvests associated rewards.
     */
    function withdraw(address _vault, uint256 _amount) external;
}
