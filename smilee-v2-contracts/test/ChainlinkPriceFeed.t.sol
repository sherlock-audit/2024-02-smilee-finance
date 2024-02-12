// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ChainlinkPriceOracle} from "@project/providers/chainlink/ChainlinkPriceOracle.sol";

/**
 * @title ChainlinkPriceFeedTest
 * @notice The test suite must be runned forking arbitrum mainnet
 */
contract ChainlinkPriceFeedTest is Test {
    address _admin = address(0x01);
    ChainlinkPriceOracle internal _priceOracle;

    // Tokens:
    address constant _USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant _WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address constant _WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Chainlink price feed aggregators:
    address constant _USDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address constant _WBTC_USD = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;
    address constant _ETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    constructor() {
        uint256 forkId = vm.createFork(vm.rpcUrl("arbitrum_mainnet"), 100768497);
        vm.selectFork(forkId);

        vm.startPrank(_admin);
        _priceOracle = new ChainlinkPriceOracle();
        _priceOracle.grantRole(_priceOracle.ROLE_ADMIN(), _admin);
        vm.stopPrank();
    }

    function testWorking() public {
        vm.startPrank(_admin);
        _priceOracle.setPriceFeed(_USDC, _USDC_USD);
        _priceOracle.setPriceFeed(_WETH, _ETH_USD);
        vm.stopPrank();

        uint256 price = _priceOracle.getPrice(_WETH, _USDC);
        assertEq(price, 1737.907785826880504424e18);
    }

    // ToDo: add more tests
}
