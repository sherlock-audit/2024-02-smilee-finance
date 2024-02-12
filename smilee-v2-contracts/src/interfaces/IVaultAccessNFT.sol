// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
    @title IVaultAccessNFT
    @notice A simple NFT associating a deposit quantity with a token id

    In order to manage wallets priority access to Smilee Vault contracts we simply want to associate a priority deposit
    amount with the token id, and implement a callback function for when deposit are processed by the vault.
 */
interface IVaultAccessNFT is IERC721 {
    /**
        @notice Gives allowed deposit info for a given token id
        @param tokenId The id of the token held by depositor
        @return amount The Vault base token amount allowed to be deposited
     */
    function priorityAmount(uint256 tokenId) external view returns (uint256 amount);

    /**
        @notice The callback function to call when deposit is processed
        @param tokenId The id of the token used to deposit
        @param amount The amount actually deposited
     */
    function decreasePriorityAmount(uint256 tokenId, uint256 amount) external;
}
