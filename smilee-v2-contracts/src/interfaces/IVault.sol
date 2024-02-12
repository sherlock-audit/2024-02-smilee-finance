// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {VaultLib} from "../lib/VaultLib.sol";
import {IVaultParams} from "./IVaultParams.sol";

/**
    Seam point for Vault usage by a DVP.
 */
interface IVault is IVaultParams {
    /**
        @notice Provides liquidity for the next epoch
        @param amount The amount of base token to deposit
        @param receiver The wallet accounted for the deposit
        @param accessTokenId The id of the owned priority NFT, if necessary (use 0 if not needed)
        @dev The shares are not directly minted to the given wallet. We need to wait for epoch change in order to know
             how many shares these assets correspond to. Shares are minted to Vault contract in `rollEpoch()` and owed
             to the receiver of deposit
        @dev The receiver can redeem its shares after the next epoch is rolled
        @dev This Vault contract need to be approved on the base token contract before attempting this operation
     */
    function deposit(uint256 amount, address receiver, uint256 accessTokenId) external;

    /**
        @notice Pre-order a withdrawal that can be executed after the end of the current epoch
        @param shares is the number of shares to convert in withdrawed liquidity
     */
    function initiateWithdraw(uint256 shares) external;

    /**
        @notice Completes a scheduled withdrawal from a past epoch.
                Uses finalized share price of the withdrawal creation epoch.
     */
    function completeWithdraw() external;

    /**
        @notice Gives the deposit information struct associated with an address
        @param account The address you want to retrieve information for
        @return epoch The epoch of the latest deposit
        @return amount The deposited amount
        @return unredeemedShares The number of shares owned by the account but held by the vault
        @return cumulativeAmount The sum of all-time deposited amounts
     */
    function depositReceipts(
        address account
    ) external view returns (uint256 epoch, uint256 amount, uint256 unredeemedShares, uint256 cumulativeAmount);

    /**
        @notice Gives the withdrawal information struct associated with an address
        @param account The address you want to retrieve information for
        @return epoch The epoch of the latest initiated withdraw
        @return shares The amount of shares for the initiated withdraw
     */
    function withdrawals(address account) external view returns (uint256 epoch, uint256 shares);

    /**
        @notice Gives portfolio composition for currently active epoch
        @return baseTokenAmount The amount of baseToken currently locked in the vault
        @return sideTokenAmount The amount of sideToken currently locked in the vault
     */
    function balances() external view returns (uint256 baseTokenAmount, uint256 sideTokenAmount);

    /**
        @notice Gives the initial notional for the current epoch (base tokens)
        @return v0_ The number of base tokens available for issuing options
     */
    function v0() external view returns (uint256 v0_);

    /**
        @notice Gives the dead status of the vault
     */
    function dead() external view returns (bool);

    /**
        @notice Adjusts the portfolio by trading the given amount of side tokens
        @param sideTokensAmount The amount of side tokens to buy (positive value) / sell (negative value)
        @return baseTokens The amount of exchanged base tokens
     */
    function deltaHedge(int256 sideTokensAmount) external returns (uint256 baseTokens);

    /**
        @notice Updates Vault State with the amount of reserved payoff
     */
    function reservePayoff(uint256 residualPayoff) external;

    /**
        @notice Tranfers an amount of reserved payoff to the user
        @param recipient The address receiving the quantity
        @param amount The number of base tokens to move
        @param isPastEpoch Flag to tell if the payoff is for an expired position
     */
    function transferPayoff(address recipient, uint256 amount, bool isPastEpoch) external;

    function vaultState()
        external view
        returns (
            uint256 v0,
            uint256 pendingDeposit,
            uint256 pendingWithdraws,
            uint256 pendingPayoffs,
            uint256 totalDeposit,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead_,
            bool killed
        );
}
