// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";

contract MarketOracleTest is Test {

    MarketOracle marketOracle;

    address admin = address(777);
    address baseToken = address(111);
    address sideToken = address(222);

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.startPrank(admin);
        
        marketOracle = new MarketOracle();
        marketOracle.grantRole(marketOracle.ROLE_ADMIN(), admin);

        vm.stopPrank();       
    }

    function testSetMaxDelay() public {
        uint256 timeWindow = 86400;
        uint256 newDelay = 2 hours;

        vm.prank(admin);
        marketOracle.setDelay(baseToken, sideToken, timeWindow, newDelay, false);

        (uint256 delay,) = marketOracle.getMaxDelay(baseToken, sideToken, timeWindow);
        assertEq(newDelay, delay);
    }

    function testGetImpliedVolatilityOfTokenWithNoDelayEnabled() public {
        uint256 timeWindow = 86400;
        uint256 newDelay = 0;

        vm.prank(admin);
        marketOracle.setDelay(baseToken, sideToken, timeWindow, newDelay, true);

        (, bool disabled) = marketOracle.getMaxDelay(baseToken, sideToken, timeWindow);
        assertEq(true, disabled);


        uint256 iv = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(1e18, iv);

        vm.warp(block.timestamp + 10 days);
        iv = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(1e18, iv);

        uint256 newIvValue = 5e18;

        vm.prank(admin);
        marketOracle.setImpliedVolatility(baseToken, sideToken, timeWindow, newIvValue);

        iv = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(newIvValue, iv);

        vm.warp(block.timestamp + 10 days);
        iv = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(newIvValue, iv);


    }

    function getDefaultMaxDelay() public {
        uint256 timeWindow = 86400;

        (uint256 delay,) = marketOracle.getMaxDelay(baseToken, sideToken, timeWindow);
        assertEq(1 hours, delay);
    }

    function testSetImpliedVolatility() public {
        uint256 timeWindow = 86400;
        uint256 newIvValue = 5e18;

        vm.prank(admin);
        marketOracle.setImpliedVolatility(baseToken, sideToken, timeWindow, newIvValue);

        uint256 iv = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);

        assertEq(newIvValue, iv);
    }

    function testSetRiskFreeRate() public {
        uint256 newRiskFreeRateValue = 0.2e18;

        vm.prank(admin);
        marketOracle.setRiskFreeRate(sideToken, newRiskFreeRateValue);

        uint256 riskFreeRate = marketOracle.getRiskFreeRate(sideToken);

        assertEq(newRiskFreeRateValue, riskFreeRate);
    }

    function testSetImpliedVolatilityOutOfAllowedRange() public {
        uint256 timeWindow = 86400;
        uint256 newIvValue = 1001e18;


        vm.prank(admin);
        vm.expectRevert(MarketOracle.OutOfAllowedRange.selector);
        marketOracle.setImpliedVolatility(baseToken, sideToken, timeWindow, newIvValue);
    }

    function testSetRiskFreeRateOutOfAllowedRange() public {
        uint256 newRiskFreeRateValue = 0.3e18;

        vm.prank(admin);
        vm.expectRevert(MarketOracle.OutOfAllowedRange.selector);
        marketOracle.setRiskFreeRate(sideToken, newRiskFreeRateValue);
    }

    /**
     * Test Get Implied volatility frequency of update.
     */
    function testGetImpliedVolatilityBeforeAndAfterDelay() public {
        uint256 timeWindow = 86400;
        uint256 newIvValue = 5e18;
        uint256 maxTollerableDelay = marketOracle.defaultMaxDelayFromLastUpdate();

        vm.prank(admin);
        marketOracle.setImpliedVolatility(baseToken, sideToken, timeWindow, newIvValue);

        // It should still work: 1 day passed from last update
        vm.warp(block.timestamp + maxTollerableDelay - 1 minutes);
        uint256 ivValue = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(newIvValue, ivValue);

        // It should revert:
        vm.warp(block.timestamp + 2 minutes);
        vm.expectRevert(abi.encodeWithSelector(MarketOracle.StaleOracleValue.selector, baseToken, sideToken, timeWindow));
        marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);

    }

    function testGetImpliedVolatilityOfNotSetTokenPair() public {
        uint256 timeWindow = 86400;

        uint256 ivValue = marketOracle.getImpliedVolatility(baseToken, sideToken, 0, timeWindow);
        assertEq(1e18, ivValue);
    }

}