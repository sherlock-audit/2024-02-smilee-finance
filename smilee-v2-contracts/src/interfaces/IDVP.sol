// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IDVPImmutables} from "./IDVPImmutables.sol";
import {IEpochControls} from "./IEpochControls.sol";

/**
    @title The interface for Smilee DVP
    @notice A DVP (Decentralized Volatility Product) is basically a generator for options on volatility
 */
interface IDVP is IDVPImmutables, IEpochControls {
    error AmountZero();
    error InvalidStrategy();

    /**
        @notice Returns the pool providing liquidity for these DVP options
        @return provider The address location of the provider contract
     */
    function vault() external view returns (address);

    /**
        @notice Returns the current price for the given option amount, function of time and available underlying assets
        @param strike The strike price the user wants to mint
        @param amountUp The amount of options to be paid for the "Up" strategy
        @param amountDown The amount of options to be paid for the "Down" strategy
        @return premium The amount of base tokens that need to be paid to mint an option
        @return fee The amount of base tokens that will be paid as fee.
     */
    function premium(
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) external view returns (uint256 premium, uint256 fee);

    /**
        @notice Returns the payoff of the given position against the underlying asset oracle price.
                Note that this will not always be equal to the actual payoff since this is determined
                by the actual swap price obtained when hedging the position
        @param epoch The position epoch
        @param strike The position strike price
        @param amountUp The position amount used to compute payoff for the "Up" strategy
        @param amountDown The position amount used to compute payoff for the "Down" strategy
        @return payoff An estimate of the current value of the position
        @return fee The amount of base tokens that will be paid as a fee
     */
    function payoff(
        uint256 epoch,
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) external view returns (uint256 payoff, uint256 fee);

    /**
        @notice Returns the utilization rate of the notional used on the relative Vault
        @return utilizationRate The utilization rate
     */
    function getUtilizationRate() external view returns (uint256);

    ////// USER ACTIONS

    /**
        @notice Creates an option with the given strategy
        @param recipient The address for which the option will be created
        @param strike The strike price for the minted option
        @param amountUp The integer quantity of options recipient wants to mint for the "Up" strategy
        @param amountDown The integer quantity of options recipient wants to mint for the "Down" strategy
        @param expectedPremium The expected market value
        @param maxSlippage The maximum accepted slippage percentage from the expected premium (denominated with 18 decimals, 1e18 = 100%)
        @param nftAccessTokenId The id of the owned access NFT, if necessary (use 0 if not needed)
        @return leverage The multiplier to obtain position notional from paid premium
        @dev strike param is ignored for IG vaults, can pass 0
     */
    function mint(
        address recipient,
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown,
        uint256 expectedPremium,
        uint256 maxSlippage,
        uint256 nftAccessTokenId
    ) external returns (uint256 leverage);

    /**
        @notice Burns an option transferring back the payoff to the owner.
        @param epoch The maturity timestamp of the option.
        @param recipient The address of the wallet that will receive the payoff, if any.
        @param strike The strike price of the burned option.
        @param amountUp The amount of notional to be burned for the "Up" strategy.
        @param amountDown The amount of notional to be burned for the "Down" strategy.
        @param expectedMarketValue The expected market value of the burned notional; ignored when epoch is not the current one.
        @param maxSlippage The maximum accepted slippage percentage from the expected value (denominated with 18 decimals, 1e18 = 100%); ignored when epoch is not the current one.
        @return paidPayoff The amount of paid payoff
        @dev After maturity, the amount parameter is ignored and all the option is burned.
     */
    function burn(
        uint256 epoch,
        address recipient,
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown,
        uint256 expectedMarketValue,
        uint256 maxSlippage
    ) external returns (uint256 paidPayoff);

}
