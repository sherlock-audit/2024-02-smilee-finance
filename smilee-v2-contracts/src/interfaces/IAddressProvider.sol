// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface IAddressProvider {
    function exchangeAdapter() external view returns (address);

    function priceOracle() external view returns (address);

    function marketOracle() external view returns (address);

    function registry() external view returns (address);

    function dvpPositionManager() external view returns (address);

    function vaultProxy() external view returns (address);

    function feeManager() external view returns (address);

    function vaultAccessNFT() external view returns (address);

    function dvpAccessNFT() external view returns (address);

}
