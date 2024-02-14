// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {MarketOracle} from "../../src/MarketOracle.sol";
import {IG} from "../../src/IG.sol";
import {TokenUtils} from "./TokenUtils.sol";
import {Utils} from "./Utils.sol";
import {Amount} from "../../src/lib/Amount.sol";
import {FinanceParameters} from "../../src/lib/FinanceIG.sol";

library DVPUtils {
    function disableOracleDelayForIG(AddressProvider ap, IG ig, address admin, Vm vm) public {
        MarketOracle marketOracle = MarketOracle(ap.marketOracle());
        vm.startPrank(admin);
        marketOracle.setDelay(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, 0, true);
        vm.stopPrank();
    }

    function debugState(IG ig) public view {
        (
            uint256 maturity,
            uint256 currentStrike,
            Amount memory initialLiquidity,
            uint256 kA,
            uint256 kB,
            uint256 theta,
            /* TimeLockedFinanceParameters timeLocked */,
            uint256 sigmaZero,
            /* internalVolatilityParameters */
        ) = ig.financeParameters();
        console.log("IG STATE ---------- maturity", maturity);
        console.log("IG STATE ---------- strike", currentStrike);
        console.log("IG STATE ---------- v0 up", initialLiquidity.up);
        console.log("IG STATE ---------- v0 down", initialLiquidity.down);
        console.log("IG STATE ---------- kA", kA);
        console.log("IG STATE ---------- kB", kB);
        console.log("IG STATE ---------- theta", theta);
        // console.log("timeLocked", timeLocked);
        console.log("IG STATE ---------- sigmaZero", sigmaZero);
    }

    /// @dev Function used to skip coverage on this file
    function testCoverageSkip() public view {}
}
