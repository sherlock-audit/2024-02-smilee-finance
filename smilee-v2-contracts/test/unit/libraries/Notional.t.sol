// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Amount, AmountHelper} from "@project/lib/Amount.sol";
import {Notional} from "@project/lib/Notional.sol";

contract NotionalTest is Test {
    using AmountHelper for Amount;
    using Notional for Notional.Info;

    Notional.Info data;

    function testShareOfPayoff() public {
        // set pre-conditions:
        uint256 referenceStrike = 1234e18;
        Amount memory usedLiquidity = Amount({
            up: 2e18,
            down: 2e18
        });
        data.used[referenceStrike] = usedLiquidity;
        Amount memory accountedPayoff = Amount({
            up: 1e18,
            down: 1e18
        });
        data.payoff[referenceStrike] = accountedPayoff;

        // check the owed payoffs for different combinations of amounts:
        Amount memory user = Amount({
            up: 1e18,
            down: 1e18
        });
        Amount memory shareOfPayoff = data.shareOfPayoff(referenceStrike, user, 18);
        assertEq(0.5e18, shareOfPayoff.up);
        assertEq(0.5e18, shareOfPayoff.down);

        user = Amount({
            up: 0.5e18,
            down: 1.5e18
        });
        shareOfPayoff = data.shareOfPayoff(referenceStrike, user, 18);
        assertEq(0.25e18, shareOfPayoff.up);
        assertEq(0.75e18, shareOfPayoff.down);

        user = Amount({
            up: 0,
            down: 1e18
        });
        shareOfPayoff = data.shareOfPayoff(referenceStrike, user, 18);
        assertEq(0, shareOfPayoff.up);
        assertEq(0.5e18, shareOfPayoff.down);

        user = Amount({
            up: 0,
            down: 0
        });
        shareOfPayoff = data.shareOfPayoff(referenceStrike, user, 18);
        assertEq(0, shareOfPayoff.up);
        assertEq(0, shareOfPayoff.down);

        user = Amount({
            up: 2e18,
            down: 2e18
        });
        shareOfPayoff = data.shareOfPayoff(referenceStrike, user, 18);
        assertEq(1e18, shareOfPayoff.up);
        assertEq(1e18, shareOfPayoff.down);
    }

    function testPostTradeUtilizationRate() public {
        // set pre-conditions:
        uint256 referenceStrike = 1234e18;
        Amount memory totalLiquidity = Amount({
            up: 2e18,
            down: 2e18
        });
        data.initial[referenceStrike] = totalLiquidity;
        Amount memory usedLiquidity = Amount({
            up: 1e18,
            down: 1e18
        });
        data.used[referenceStrike] = usedLiquidity;

        Amount memory trade = Amount({
            up: 0,
            down: 0
        });
        uint256 postTradeUtilizationRate = data.postTradeUtilizationRate(referenceStrike, trade, true, 18);
        assertEq(0.5e18, postTradeUtilizationRate);

        // Simulate some trade:
        trade = Amount({
            up: 0.5e18,
            down: 0.5e18
        });
        postTradeUtilizationRate = data.postTradeUtilizationRate(referenceStrike, trade, true, 18);
        assertEq(0.75e18, postTradeUtilizationRate);

        trade = Amount({
            up: 0.5e18,
            down: 0.5e18
        });
        postTradeUtilizationRate = data.postTradeUtilizationRate(referenceStrike, trade, false, 18);
        assertEq(0.25e18, postTradeUtilizationRate);
    }
}
