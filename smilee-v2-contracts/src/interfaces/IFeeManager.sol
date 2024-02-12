// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IFeeManager {
    /**
        Computes trade fee for buying options
        @param dvp The address of the DVP on which the trade is being performed
        @param expiry The expiry timestamp of current epoch of the DVP
        @param notional The notional of the traded option
        @param premium The premium of the traded option (cost)
        @param tokenDecimals Decimals of token
        @return fee The required fee
        @return minFee The required minimum fee paid for each trade which is transferred to the vault
     */
    function tradeBuyFee(
        address dvp,
        uint256 expiry,
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals
    ) external view returns (uint256 fee, uint256 minFee);

    /**
        Computes trade fee for selling options
        @param dvp The address of the DVP on which the trade is being performed
        @param expiry The expiry timestamp of current epoch of the DVP
        @param notional The notional of the traded option
        @param currPremium The current premium of the traded option (user payoff)
        @param entryPremium The premium paid for the option
        @param tokenDecimals # of decimals in the notation of the option base token
        @return fee The required fee
        @return minFee The required minimum fee paid for each trade which is transferred to the vault

     */
    function tradeSellFee(
        address dvp,
        uint256 expiry,
        uint256 notional,
        uint256 currPremium,
        uint256 entryPremium,
        uint8 tokenDecimals
    ) external view returns (uint256 fee, uint256 minFee);

    /**
     * Receive fee from sender and record the value into account
     * @param feeAmount The amount transfered to the FeeManager
     */
    function receiveFee(uint256 feeAmount) external;

    /**
     * Track the vault fee amount
     * @param vault The vault the fee will be transfered on.
     * @param feeAmount The fee amount transfered to the vault.
     */
    function trackVaultFee(address vault, uint256 feeAmount) external;

    /**
     *
     * @param receiver The address where fees will send to.
     * @param sender The address who has paid fees.
     * @param feeAmount The fee amount to withdraw.
     */
    function withdrawFee(address receiver, address sender, uint256 feeAmount) external;
}
