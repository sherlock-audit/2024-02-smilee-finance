// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {SD59x18, sd, convert as convertint} from "@prb/math/SD59x18.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";

/// @title Implementation of core financial computations for Smilee protocol
library FinanceIGDelta {
    /// @notice A wrapper for the input parameters of delta perc functions
    struct Parameters {
        // strike
        uint256 k;
        // lower bound liquidity range
        uint256 kA;
        // upper bound liquidity range
        uint256 kB;
        // reference price
        uint256 s;
        // theta factor
        uint256 theta;
    }

    struct DeltaHedgeParameters {
        int256 igDBull;
        int256 igDBear;
        uint8 baseTokenDecimals;
        uint8 sideTokenDecimals;
        uint256 initialLiquidityBull;
        uint256 initialLiquidityBear;
        uint256 availableLiquidityBull;
        uint256 availableLiquidityBear;
        uint256 sideTokensAmount;
        int256 notionalUp;
        int256 notionalDown;
        uint256 strike;
        uint256 theta;
        uint256 kb;
    }

    int256 internal constant _MAX_EXP = 133_084258667509499441;

    /**
        @notice Computes unitary delta hedge quantity for bull/bear options
        @param params The set of Parameters to compute deltas
        @return igDBull The unitary integer quantity of side token to hedge a bull position
        @return igDBear The unitary integer quantity of side token to hedge a bear position
        @dev the formulas are the ones for different ranges of liquidity
    */
    function deltaHedgePercentages(Parameters calldata params) external pure returns (int256 igDBull, int256 igDBear) {
        igDBull = bullDelta(params.k, params.kB, params.s, params.theta);
        igDBear = bearDelta(params.k, params.kA, params.s, params.theta);
    }

    /**
        @notice Gives the amount of side tokens to swap in order to hedge protocol delta exposure
        @param params The DeltaHedgeParameters info
        @return tokensToSwap An integer amount, positive when there are side tokens in excess (need to sell) and negative vice versa
        @dev This is what's called `h` in the papers
     */
    function deltaHedgeAmount(DeltaHedgeParameters memory params) public pure returns (int256 tokensToSwap) {
        params.initialLiquidityBull = AmountsMath.wrapDecimals(params.initialLiquidityBull, params.baseTokenDecimals);
        params.initialLiquidityBear = AmountsMath.wrapDecimals(params.initialLiquidityBear, params.baseTokenDecimals);
        params.availableLiquidityBull = AmountsMath.wrapDecimals(
            params.availableLiquidityBull,
            params.baseTokenDecimals
        );
        params.availableLiquidityBear = AmountsMath.wrapDecimals(
            params.availableLiquidityBear,
            params.baseTokenDecimals
        );

        uint256 notionalBull = AmountsMath.wrapDecimals(SignedMath.abs(params.notionalUp), params.baseTokenDecimals);
        uint256 notionalBear = AmountsMath.wrapDecimals(SignedMath.abs(params.notionalDown), params.baseTokenDecimals);
        params.sideTokensAmount = AmountsMath.wrapDecimals(params.sideTokensAmount, params.sideTokenDecimals);

        uint256 protoNotionalBull = params.notionalUp >= 0
            ? ud(params.availableLiquidityBull).sub(ud(notionalBull)).unwrap()
            : ud(params.availableLiquidityBull).add(ud(notionalBull)).unwrap();

        uint256 protoNotionalBear = params.notionalDown >= 0
            ? ud(params.availableLiquidityBear).sub(ud(notionalBear)).unwrap()
            : ud(params.availableLiquidityBear).add(ud(notionalBear)).unwrap();

        uint256 protoDBull = 2 * ud(SignedMath.abs(params.igDBull))
            .mul(ud(protoNotionalBull))
            .unwrap();
        uint256 protoDBear = 2 * ud(SignedMath.abs(params.igDBear))
            .mul(ud(protoNotionalBear))
            .unwrap();

        uint256 deltaLimit;
        {
            UD60x18 v0 = ud(params.initialLiquidityBull + params.initialLiquidityBear);
            UD60x18 strike = ud(params.strike);
            UD60x18 theta = ud(params.theta);
            UD60x18 kb = ud(params.kb);
            // DeltaLimit := v0 / (θ * k) - v0 / (θ * √(K * Kb))
            deltaLimit = v0.div(theta.mul(strike)).sub(v0.div(theta.mul(strike.mul(kb).sqrt()))).unwrap();
        }

        tokensToSwap =
            SignedMath.revabs(protoDBull, params.igDBull >= 0) +
            SignedMath.revabs(protoDBear, params.igDBear >= 0) +
            SignedMath.castInt(params.sideTokensAmount) -
            SignedMath.castInt(deltaLimit);

        // due to sqrt computation error, sideTokens to sell may be very few more than available
        if (SignedMath.abs(tokensToSwap) > params.sideTokensAmount) {
            if (SignedMath.abs(tokensToSwap) - params.sideTokensAmount < params.sideTokensAmount / 10000) {
                tokensToSwap = SignedMath.revabs(params.sideTokensAmount, true);
            }
        }
        params.sideTokensAmount = SignedMath.abs(tokensToSwap);
        params.sideTokensAmount = AmountsMath.unwrapDecimals(params.sideTokensAmount, params.sideTokenDecimals);
        tokensToSwap = SignedMath.revabs(params.sideTokensAmount, tokensToSwap >= 0);
    }

    ////// HELPERS //////

    /**
        Δ_bull = (1 / θ) * F
        F = {
            * 0                     if (S < K)
            * (1 - √(K / Kb)) / K   if (S > Kb)
            * 1 / K - 1 / √(S * K)  if (K < S < Kb)
        }
    */
    function bullDelta(uint256 k, uint256 kB, uint256 s, uint256 theta) internal pure returns (int256) {
        SD59x18 delta;
        if (s <= k) {
            return 0;
        }
        if (s > kB) {
            delta = (convertint(1).sub((sd(int256(k)).div(sd(int256(kB)))).sqrt())).div(sd(int256(k)));
        } else {
            // if (k < s < kB)
            delta = _inRangeDelta(k, s);
        }
        return delta.div(sd(int256(theta))).unwrap();
    }

    /**
        Δ_bear = (1 / θ) * F
        F = {
            * (1 - √(K / Ka)) / K   if (S < Ka)
            * 0                     if (S > K)
            * 1 / K - 1 / √(S * K)  if (Ka < S < K)
        }
    */
    function bearDelta(uint256 k, uint256 kA, uint256 s, uint256 theta) internal pure returns (int256) {
        SD59x18 delta;
        if (s >= k) {
            return 0;
        }
        if (s < kA) {
            delta = (convertint(1).sub((sd(int256(k)).div(sd(int256(kA)))).sqrt())).div(sd(int256(k)));
        } else {
            // if (kA < s < k)
            delta = _inRangeDelta(k, s);
        }
        return delta.div(sd(int256(theta))).unwrap();
    }

    /// @dev (1 / K) - 1 / √(S * K)
    function _inRangeDelta(uint256 k, uint256 s) internal pure returns (SD59x18) {
        return (convertint(1).div(sd(int256(k)))).sub(convertint(1).div((sd(int256(s)).mul(sd(int256(k))).sqrt())));
    }
}
