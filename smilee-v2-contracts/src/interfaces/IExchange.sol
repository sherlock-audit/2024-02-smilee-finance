// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ISwapAdapter} from "./ISwapAdapter.sol";

interface IExchange is ISwapAdapter {
    /**
        @notice Preview how much tokenOut will be given back in exchange of an amount of tokenIn
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param amountIn The amount of input token to be provided
        @return amountOut The amount of output tokens that will be given back in exchange of `amountIn`
        @dev Allows to preview the amount of tokenOut that will be swapped by `swapIn`
     */
    function getOutputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /**
        @notice Preview how much tokenIn will be taken in exchange for an amount of tokenOut
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param amountOut The amount of output token to be provided
        @return amountIn The amount of input tokens that will be taken in exchange of `amountOut`
        @dev Allows to preview the amount of tokenIn that will be swapped by `swapOut`
     */
    function getInputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256 amountIn);

    /**
        @notice Preview how much tokenIn will be taken at maximum in the given trade
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param amountOut The amount of output token to be provided
        @return amountInMax The maximum amount of input tokens that will be taken
     */
    function getInputAmountMax(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256 amountInMax);
}
