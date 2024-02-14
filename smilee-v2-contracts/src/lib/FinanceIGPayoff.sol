// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";

/**
    @title Implementation of core financial computations for Smilee protocol
 */
library FinanceIGPayoff {
    /**
        @notice Computes concentrated liquidity impermanent gain percentage when current price falls in liquidity range
        @param sdivk Current side token price over strike price
        @param theta Theta coefficient
        @return inRangePayoffPerc The impermanent gain
     */
    function igPayoffInRange(uint256 sdivk, uint256 theta) public pure returns (uint256 inRangePayoffPerc) {
        UD60x18 sdivkx18 = ud(sdivk);
        UD60x18 thetax18 = ud(theta);

        UD60x18 res = (convert(1).add(sdivkx18).sub((convert(2).mul(sdivkx18.sqrt())))).div(thetax18);
        inRangePayoffPerc = res.unwrap();
    }

    /**
        @notice Computes concentrated liquidity impermanent gain percentage when current price falls out of liquidity range
        @param sdivk Current side token price over strike price
        @param theta Theta coefficient
        @param k Ref. strike
        @param kbound Upper or lower bound of the range
        @return outRangePayoffPerc The impermanent gain
     */
    function igPayoffOutRange(
        uint256 sdivk,
        uint256 theta,
        uint256 k,
        uint256 kbound
    ) public pure returns (uint256 outRangePayoffPerc) {
        UD60x18 one = convert(1);
        UD60x18 kDivKboundRtd = ud(k).div(ud(kbound)).sqrt();
        UD60x18 kboundDivKRtd = ud(kbound).div(ud(k)).sqrt();

        bool c2Pos = kDivKboundRtd.gte(one);
        UD60x18 c2Abs = ud(sdivk).mul(c2Pos ? kDivKboundRtd.sub(one) : one.sub(kDivKboundRtd));
        UD60x18 num;
        if (c2Pos) {
            num = one.sub(c2Abs).sub(kboundDivKRtd);
        } else {
            num = one.add(c2Abs).sub(kboundDivKRtd);
        }
        return num.div(ud(theta)).unwrap();
    }

    /**
        @notice Computes payoff percentage for impermanent gain up / down strategies
        @param s Current side token price
        @param k Ref. strike
        @param ka Lower range strike bound
        @param kb Upper range strike bound
        @param theta Theta coefficient
        @return igPOBull The percentage payoff for bull strategy
        @return igPOBear The percentage payoff for bear strategy
     */
    function igPayoffPerc(
        uint256 s,
        uint256 k,
        uint256 ka,
        uint256 kb,
        uint256 theta
    ) external pure returns (uint256 igPOBull, uint256 igPOBear) {
        uint256 sk = ud(s).div(ud(k)).unwrap();
        igPOBull = s <= k ? 0 : s > kb ? igPayoffOutRange(sk, theta, k, kb) : igPayoffInRange(sk, theta);
        igPOBear = s >= k ? 0 : s < ka ? igPayoffOutRange(sk, theta, k, ka) : igPayoffInRange(sk, theta);
    }
}
