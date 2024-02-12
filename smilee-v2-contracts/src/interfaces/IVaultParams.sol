// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IVaultParams {
    /**
        @notice The base token in the pair of the DVP
        @return baseToken The contract address of the base token
     */
    function baseToken() external view returns (address baseToken);

    /**
        @notice The side token in the pair of the DVP
        @return sideToken The contract address of the side token
     */
    function sideToken() external view returns (address sideToken);
}
