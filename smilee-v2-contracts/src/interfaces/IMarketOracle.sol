// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

/// @dev everything is expressed in Wad (18 decimals)
interface IMarketOracle {
    function getImpliedVolatility(
        address token0,
        address token1,
        uint256 strikePrice,
        uint256 frequency
    ) external view returns (uint256 iv);

    function getRiskFreeRate(address token0) external view returns (uint256 rate);
}
