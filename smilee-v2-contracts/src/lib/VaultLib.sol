// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

library VaultLib {
    bytes4 constant DeadMarketReason = bytes4(keccak256("MarketReason"));
    bytes4 constant DeadManualKillReason = bytes4(keccak256("ManualKill"));

    struct VaultState {
        VaultLiquidity liquidity;
        VaultWithdrawals withdrawals;
        // Vault become dead when it's killed manually
        bool dead;
        // The flag killed is index of the will of the vault to be killed in the next epoch
        bool killed; 
    }

    struct VaultLiquidity {
        // Liquidity initially used by the associated DVP
        uint256 lockedInitially;
        // Liquidity from new deposits
        uint256 pendingDeposits;
        // Liquidity reserved for withdrawals
        uint256 pendingWithdrawals;
        // Liquindity reserved for payoffs
        uint256 pendingPayoffs;
        // Liquidity to put aside before the next epoch
        uint256 newPendingPayoffs;
        // Cumulative base token deposits across all accounts
        uint256 totalDeposit;
    }

    struct VaultWithdrawals {
        // Cumulated shares held by Vault for initiated withdraws (accounting purposes)
        uint256 heldShares;
        // Number of shares held by the contract because of inititateWithdraw() calls done during the current epoch
        uint256 newHeldShares;
    }

    struct DepositReceipt {
        uint256 epoch;
        uint256 amount;
        uint256 unredeemedShares;
        uint256 cumulativeAmount;
    }

    struct Withdrawal {
        uint256 epoch; // Epoch in which the withdraw flow started
        uint256 shares; // Number of shares withdrawn
    }

    /**
        @notice Returns the number of shares corresponding to given amount of asset
        @param assetAmount The amount of assets to be converted to shares
        @param sharePrice The price (in asset) for 1 share
        @param tokenDecimals The decimals in the ERC20 asset
     */
    function assetToShares(uint256 assetAmount, uint256 sharePrice, uint8 tokenDecimals) public pure returns (uint256) {
        // If sharePrice goes to zero, the asset cannot minted, this means the assetAmount is to rescue
        if (sharePrice == 0) {
            return 0;
        }
        if (assetAmount == 0) {
            return 0;
        }

        return (assetAmount * 10 ** tokenDecimals) / sharePrice;
    }

    /**
        @notice Returns the amount of asset corresponding to given number of shares
        @param shareAmount The number of shares to be converted to asset
        @param sharePrice The price (in asset) for 1 share
        @param tokenDecimals The decimals in the ERC20 asset
     */
    function sharesToAsset(
        uint256 shareAmount,
        uint256 sharePrice,
        uint8 tokenDecimals
    ) external pure returns (uint256) {
        return (shareAmount * sharePrice) / 10 ** tokenDecimals;
    }

    /**
        @notice Returns the asset value of a share for the given inputs
        @param assetAmount The number of assets
        @param shareAmount The number of shares
        @param tokenDecimals The decimals in the ERC20 asset
        @return price The price (in asset) for 1 share
     */
    function pricePerShare(
        uint256 assetAmount,
        uint256 shareAmount,
        uint8 tokenDecimals
    ) external pure returns (uint256 price) {
        uint256 shareUnit = 10 ** tokenDecimals;
        if (shareAmount == 0) {
            // 1:1 ratio
            return shareUnit;
        }
        assetAmount = assetAmount * shareUnit; // Fix decimals in the following computation
        return assetAmount / shareAmount;
    }

    /**
        @notice Returns the shares unredeemed by the user given their DepositReceipt
        @param depositReceipt The user's deposit receipt
        @param currentEpoch The `epoch` stored on the vault
        @param sharePrice The price (in asset) for 1 share
        @param tokenDecimals The decimals in the ERC20 asset (and therefore in the share)
        @return unredeemedShares The user's virtual balance of shares that are owed
     */
    function getSharesFromReceipt(
        DepositReceipt calldata depositReceipt,
        uint256 currentEpoch,
        uint256 sharePrice,
        uint8 tokenDecimals
    ) external pure returns (uint256 unredeemedShares) {
        if (depositReceipt.epoch == 0 || depositReceipt.epoch == currentEpoch) {
            return depositReceipt.unredeemedShares;
        }

        uint256 sharesFromRound = assetToShares(depositReceipt.amount, sharePrice, tokenDecimals);
        return depositReceipt.unredeemedShares + sharesFromRound;
    }
}
