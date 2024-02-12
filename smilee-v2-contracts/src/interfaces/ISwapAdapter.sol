// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface ISwapAdapter {

    error InsufficientInput();

    /**
        @notice Swaps the given amount of tokenIn tokens in exchange for some tokenOut tokens
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param amountIn The amount of input token to be provided
        @return amountOut The amount of output token given by the exchange
        @dev The client choose how much tokenIn it wants to provide
        @dev The client needs to approve the amountIn of tokenIn
     */
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);

    /**
        @notice Swaps some tokenIn tokens in exchange for the given amount of tokenOut tokens
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param amountOut The amount of output token to be obtained
        @param preApprovedAmountIn The amount of input token that the caller has approved to be moved
        @return amountIn The amount of input token that has been spent
        @dev The client choose how much tokenOut it wants to obtain
        @dev The client needs to approve the getInputAmount of tokenIn
     */
    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 preApprovedAmountIn
    ) external returns (uint256 amountIn);
}
