// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
    @title IDVPAccessNFT
    @notice A simple NFT allowing trade with a cap quantity for each trade with a token id

    In order to manage wallets access to trade Smilee DVP contracts we simply want to associate a cap
    amount with the token id.
    // and implement a callback function for when trade are processed by the DVP.
 */
interface IDVPAccessNFT is IERC721 {
    /**
        @notice Gives allowed trade info for a given token id
        @param tokenId The id of the token held by trader
        @return capAmount The maximum tradable notional amount of base token amount allowed to be traded
     */
    function capAmount(uint256 tokenId) external view returns (uint256 capAmount);

    /**
        @notice The callback function to check if the user is allowed to trade.
        @param tokenId The id of the token used to trade
        @param amount The notional amount to be traded
     */
    function checkCap(uint256 tokenId, uint256 amount) external;
}
