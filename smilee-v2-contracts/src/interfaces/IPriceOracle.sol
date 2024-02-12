// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPriceOracle {
    /**
        @notice Return token0 unit price in token1 currency
        @param token0 Address of token 0
        @param token1 Address of token 1
        @return price Ratio with 18 decimals
    */
    function getPrice(address token0, address token1) external view returns (uint256 price);
}
