// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {sd} from "@prb/math/SD59x18.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {Gaussian} from "@solstat/Gaussian.sol";
import {AmountsMath} from "./AmountsMath.sol";
import {SignedMath} from "./SignedMath.sol";

/// @title Implementation of core financial computations for Smilee protocol
library FinanceIGPrice {
    error PriceZero();
    error OutOfRange(string varname, uint256 value);
    error NegativePriceDetected();

    /// @notice A wrapper for the input parameters of delta and price functions
    struct Parameters {
        ////// INPUTS //////
        // risk free rate
        uint256 r;
        // implied volatility
        uint256 sigma;
        // strike
        uint256 k;
        // reference price
        uint256 s;
        // time (denominated in years)
        uint256 tau;
        // concentrated liquidity range lower bound
        uint256 ka;
        // concentrated liquidity range upper bound
        uint256 kb;
        ////// DERIVED //////
        // θ = 2 - √(Ka / K) - √(K / Kb)
        uint256 teta;
    }

    /**
        @notice Computes unitary price for up/down options
        @param params The set of Parameters to compute the option price
        @return igPBull The unitary price for an up position
        @return igPBear The unitary price for a down position
     */
    function igPrices(Parameters calldata params) external pure returns (uint256 igPBull, uint256 igPBear) {
        (DTerms memory ds, DTerms memory das, DTerms memory dbs) = dTerms(params);
        NTerms memory ns = nTerms(ds);
        NTerms memory nas = nTerms(das);
        NTerms memory nbs = nTerms(dbs);

        uint256 ert = _ert(params.r, params.tau);
        uint256 sdivk = ud(params.s).div(ud(params.k)).unwrap();

        // Assume the price (up and down) is always >= 0
        {
            PriceParts memory ps = pBullParts(params, ert, sdivk, ns, nbs);
            uint256 pos = ps.p1 + ps.p2;
            uint256 neg = ps.p3 + ps.p4 + ps.p5;
            if (pos < neg) {
                // NOTE: rounding errors may yields a slightly negative number
                if (neg - pos >= 1e9) {
                    revert NegativePriceDetected();
                }
                igPBull = 0;
            } else {
                igPBull = pos - neg;
            }
        }
        {
            PriceParts memory ps = pBearParts(params, ert, sdivk, ns, nas);
            uint256 pos = ps.p1 + ps.p2;
            uint256 neg = ps.p3 + ps.p4 + ps.p5;
            if (pos < neg) {
                // NOTE: rounding errors may yields a slightly negative number
                if (neg - pos >= 1e9) {
                    revert NegativePriceDetected();
                }
                igPBear = 0;
            } else {
                igPBear = pos - neg;
            }
        }
    }

    struct DTerms {
        int256 d1; // [ ln(S / K) + ( r + σ^2 / 2 ) τ ] / σ√τ
        int256 d2; // d1 - σ√τ
        int256 d3; // d2 + σ√τ / 2
    }

    struct NTerms {
        uint256 n1; // N(d1)
        uint256 n2; // N(d2)
        uint256 n3; // N(d3)
    }

    struct PriceParts {
        uint256 p1;
        uint256 p2;
        uint256 p3;
        uint256 p4;
        uint256 p5;
    }

    /**
        @notice Computes base components for delta and price formulas
        @param params The set of Parameters to compute the option price
        @return ds ds terms computed with (price / K)
        @return das ds terms computed with (price / Ka)
        @return dbs ds terms computed with (price / Kb)
     */
    function dTerms(
        Parameters calldata params
    ) public pure returns (DTerms memory ds, DTerms memory das, DTerms memory dbs) {
        if (params.s == 0) {
            revert PriceZero();
        }

        uint256 r = ud(params.s).div(ud(params.k)).unwrap(); // S / K
        uint256 ra = ud(params.s).div(ud(params.ka)).unwrap(); // S / Ka
        uint256 rb = ud(params.s).div(ud(params.kb)).unwrap(); // S / Kb

        (uint256 sigmaTaurtd, uint256 q1) = d1Parts(params.r, params.sigma, params.tau);

        {
            int256 d1_ = d1(r, q1, sigmaTaurtd);
            int256 d2_ = d2(d1_, sigmaTaurtd);
            int256 d3_ = d3(d2_, sigmaTaurtd);
            ds = DTerms(d1_, d2_, d3_);
        }

        {
            int256 d1a_ = d1(ra, q1, sigmaTaurtd);
            int256 d2a_ = d2(d1a_, sigmaTaurtd);
            int256 d3a_ = d3(d2a_, sigmaTaurtd);
            das = DTerms(d1a_, d2a_, d3a_);
        }

        {
            int256 d1b_ = d1(rb, q1, sigmaTaurtd);
            int256 d2b_ = d2(d1b_, sigmaTaurtd);
            int256 d3b_ = d3(d2b_, sigmaTaurtd);
            dbs = DTerms(d1b_, d2b_, d3b_);
        }
    }

    function nTerms(DTerms memory ds) public pure returns (NTerms memory) {
        return NTerms(
            ds.d1 < -type(int256).max / 1e18 ? 0 : uint256(Gaussian.cdf(ds.d1)),
            ds.d2 < -type(int256).max / 1e18 ? 0 : uint256(Gaussian.cdf(ds.d2)),
            ds.d3 < -type(int256).max / 1e18 ? 0 : uint256(Gaussian.cdf(ds.d3))
        );
    }

    /// @dev σ√τ AND ( r + σ^2 / 2 ) τ
    function d1Parts(uint256 r, uint256 sigma, uint256 tau) public pure returns (uint256 sigmaTaurtd, uint256 q1) {
        q1 = ud(r).add(ud((sigma * sigma) / 2e18)).mul(ud(tau)).unwrap();
        sigmaTaurtd = _sigmaTaurtd(sigma, tau);
    }

    /// @dev [ ln(S / K) + ( r + σ^2 / 2 ) τ ] / σ√τ
    function d1(uint256 priceStrikeRt, uint256 q1, uint256 sigmaTaurtd) public pure returns (int256 d1_) {
        if (priceStrikeRt == 0) {
            return -type(int256).max;
        }
        int256 q0 = ud(priceStrikeRt).intoSD59x18().ln().unwrap();
        (uint256 sumQty, bool sumPos) = SignedMath.sum(q0, q1);
        uint256 res = ud(sumQty).div(ud(sigmaTaurtd)).unwrap();

        return SignedMath.revabs(res, sumPos);
    }

    /// @dev d1 - σ√τ
    function d2(int256 d1_, uint256 sigmaTaurtd) public pure returns (int256) {
        if (d1_ <= -(type(int256).max - SignedMath.castInt(sigmaTaurtd))) {
            return -type(int256).max;
        }
        return d1_ - SignedMath.castInt(sigmaTaurtd);
    }

    /// @dev d2 + σ√τ / 2
    function d3(int256 d2_, uint256 sigmaTaurtd) public pure returns (int256) {
        return d2_ + int256(sigmaTaurtd / 2);
    }

    function pBullParts(
        Parameters memory params,
        uint256 ert,
        uint256 sdivk,
        NTerms memory ns,
        NTerms memory nbs
    ) public pure returns (PriceParts memory) {
        return
            PriceParts(
                pbull1(ert, ns.n2),
                pbull2(sdivk, ns.n1),
                pbull3(sdivk, params.sigma, params.r, params.tau, ns.n3, nbs.n3),
                pbull4(params.s, _kkrtd(params.k, params.kb), nbs.n1),
                pbull5(ert, _kdivkrtd(params.k, params.kb), nbs.n2)
            );
    }

    function pBearParts(
        Parameters memory params,
        uint256 ert,
        uint256 sdivk,
        NTerms memory ns,
        NTerms memory nas
    ) public pure returns (PriceParts memory) {
        return
            PriceParts(
                pbear1(ert, ns.n2),
                pbear2(sdivk, ns.n1),
                pbear3(sdivk, params.sigma, params.r, params.tau, ns.n3, nas.n3),
                pbear4(params.s, _kkrtd(params.k, params.ka), nas.n1),
                pbear5(ert, _kdivkrtd(params.k, params.ka), nas.n2)
            );
    }

    /// @dev e^-(r τ) * (1 - N(d2))
    function pbear1(uint256 ert, uint256 n2) public pure returns (uint256) {
        return ud(ert).mul(convert(1).sub(ud(n2))).unwrap();
    }

    /// @dev S/K * (1 - N(d1))
    function pbear2(uint256 sdivk, uint256 n1) public pure returns (uint256) {
        return ud(sdivk).mul(convert(1).sub(ud(n1))).unwrap();
    }

    /// @dev 2 [ √(S / K) e^-(r / 2 + σ^2 / 8)τ ] * [ N(d3a) - N(d3) ]
    function pbear3(
        uint256 sdivk,
        uint256 sigma,
        uint256 r,
        uint256 tau,
        uint256 n3,
        uint256 n3a
    ) public pure returns (uint256) {
        UD60x18 sdivkRtd = ud(sdivk).sqrt();
        UD60x18 e1 = sd(SignedMath.neg(_boexp(r, sigma, tau))).exp().intoUD60x18();
        return 2 * sdivkRtd.mul(e1).mul(ud(n3a).sub(ud(n3))).unwrap();
    }

    /// @dev S / √(K * K_a) * (1 - N(d1a))
    function pbear4(uint256 s, uint256 kkartd, uint256 n1a) public pure returns (uint256) {
        return s * convert(1).sub(ud(n1a)).unwrap() / kkartd;
    }

    /// @dev e^-(r τ) * √(K_a / K) * N(1 - d2a)
    function pbear5(uint256 ert, uint256 kadivkrtd, uint256 n2a) public pure returns (uint256) {
        return ud(ert).mul(ud(kadivkrtd).mul(convert(1).sub(ud(n2a)))).unwrap();
    }

    /// @dev e^-(r τ) * N(d2)
    function pbull1(uint256 ert, uint256 n2) public pure returns (uint256) {
        return ud(ert).mul(ud(n2)).unwrap();
    }

    /// @dev S/K * N(d1)
    function pbull2(uint256 sdivk, uint256 n1) public pure returns (uint256) {
        return ud(sdivk).mul(ud(n1)).unwrap();
    }

    /// @dev 2 [ √(S / K) e^-(r / 2 + σ^2 / 8)τ ] * [ N(d3) - N(d3b) ]
    function pbull3(
        uint256 sdivk,
        uint256 sigma,
        uint256 r,
        uint256 tau,
        uint256 n3,
        uint256 n3b
    ) public pure returns (uint256) {
        UD60x18 sdivkRtd = ud(sdivk).sqrt();
        UD60x18 e1 = sd(SignedMath.neg(_boexp(r, sigma, tau))).exp().intoUD60x18();
        return 2 * sdivkRtd.mul(e1).mul(ud(n3).sub(ud(n3b))).unwrap();
    }

    /// @dev S / √(K K_b) * N(d1b)
    function pbull4(uint256 s, uint256 kkbrtd, uint256 n1b) public pure returns (uint256) {
        return s * n1b / kkbrtd;
    }

    /// @dev e^-(r τ) * √(K_b / K) * N(d2b)
    function pbull5(uint256 ert, uint256 kbdivkrtd, uint256 n2b) public pure returns (uint256) {
        return ud(ert).mul(ud(kbdivkrtd).mul(ud(n2b))).unwrap();
    }

    ////// HELPERS //////

    /// @dev (r / 2 + σ^2 / 8)τ
    function _boexp(uint256 r, uint256 sigma, uint256 tau) public pure returns (uint256) {
        return ud(tau).mul(ud(r / 2 + SignedMath.pow2(int256(sigma)) / 8)).unwrap();
    }

    /// @dev e^-(r τ)
    function _ert(uint256 r, uint256 tau) public pure returns (uint256) {
        return sd(SignedMath.neg(ud(r).mul(ud(tau)).unwrap())).exp().intoUD60x18().unwrap();
    }

    /// @dev e^-(r / 2 + σ^2 / 8)τ
    function er2sig8(uint256 r, uint256 sigma, uint256 tau) public pure returns (uint256) {
        UD60x18 exp = ud(tau).mul(ud(r / 2 + SignedMath.pow2(int256(sigma)) / 8));
        return sd(SignedMath.neg(exp.unwrap())).exp().intoUD60x18().unwrap();
    }

    /// @dev √(K K_<a|b>)
    function _kkrtd(uint256 k, uint256 krange) public pure returns (uint256) {
        UD60x18 res = (ud(k).mul(ud(krange))).sqrt();
        uint256 resUnwrapped = res.unwrap();
        if (resUnwrapped == 0) {
            return 1;
        }
        return resUnwrapped;
    }

    /// @dev √(K_<a|b> / K)
    function _kdivkrtd(uint256 k, uint256 krange) public pure returns (uint256) {
        UD60x18 res = (ud(krange).div(ud(k))).sqrt();
        return res.unwrap();
    }

    /// @dev 2 - √(Ka / K) - √(K / Kb)
    function _teta(uint256 k, uint256 ka, uint256 kb) public pure returns (uint256 teta) {
        UD60x18 kx18 = ud(k);
        UD60x18 kax18 = ud(ka);
        UD60x18 kbx18 = ud(kb);

        UD60x18 res = convert(2).sub((kax18.div(kx18)).sqrt()).sub((kx18.div(kbx18)).sqrt());
        return res.unwrap();
    }

    /// @dev σ√τ
    function _sigmaTaurtd(uint256 sigma, uint256 tau) public pure returns (uint256) {
        return ud(sigma).mul(ud(tau).sqrt()).unwrap();
    }

    //////  OTHER //////

    struct LiquidityRangeParams {
        // The reference strike
        uint256 k;
        // The token's pair volatility; symbolic values in [0, 1] ?
        uint256 sigma;
        // A multiplier for the token's pair volatility
        uint256 sigmaMultiplier;
        // Number of years from now to expiry
        uint256 yearsToMaturity;
    }

    /**
        @notice Computes the range (kA, kB)
        @param params The parameters.
        @return kA The lower limit of the liquidity range.
        @return kB The upper limit of the liquidity range.
        @dev All the values are expressed in Wad.
     */
    function liquidityRange(LiquidityRangeParams calldata params) public pure returns (uint256 kA, uint256 kB) {
        uint256 mSigmaT = ud(params.sigma)
            .mul(ud(params.sigmaMultiplier))
            .mul(ud(params.yearsToMaturity).sqrt())
            .unwrap();

        kA = ud(params.k).mul(sd(SignedMath.neg(mSigmaT)).exp().intoUD60x18()).unwrap();
        kB = ud(params.k).mul(ud(mSigmaT).exp()).unwrap();

        if (kA == 0) {
            kA = 1;
        }
    }

    struct TradeVolatilityParams {
        // The baseline volatility at epoch start
        uint256 sigma0;
        // A multiplier for the utilization rate; must be greater or equal to one
        uint256 utilizationRateFactor;
        // A time decay factor
        uint256 timeDecay;
        // The utilization rate of the vault deposits
        uint256 utilizationRate;
        // The epoch duration (maturity timestamp - last maturity timestamp)
        uint256 duration;
        // The epoch start timestamp
        uint256 initialTime;
    }

    /**
        @notice Computes the trade volatility
        @param params The parameters
        @return sigma_hat the trade volatility.
        @dev All the non-timestamp values are expressed in Wad.
     */
    function tradeVolatility(TradeVolatilityParams calldata params) public view returns (uint256 sigma_hat) {
        // sigma0 * (1 + ur^3 * (n - 1)) * (T - (0.25 * t)) / T
        uint256 urQubic = uint256(SignedMath.pow3(int256(params.utilizationRate)));
        // bvf = 1 + ur^3 * (n - 1)
        UD60x18 baselineVolatilityFactor = convert(1).add(
            ud(urQubic).mul(ud(params.utilizationRateFactor).sub(convert(1)))
        );
        UD60x18 timeElapsed = convert(block.timestamp - params.initialTime);
        // tf = (T - (decay * Δt)) / T
        UD60x18 timeFactor = (convert(params.duration).sub(ud(params.timeDecay).mul(timeElapsed))).div(
            convert(params.duration)
        );

        return ud(params.sigma0).mul(baselineVolatilityFactor).mul(timeFactor).unwrap();
    }

    function getMarketValue(
        uint256 theta,
        uint256 amountUp,
        uint256 priceUp,
        uint256 amountDown,
        uint256 priceDown,
        uint8 decimals
    ) public pure returns (uint256 marketValue_) {
        amountUp = AmountsMath.wrapDecimals(amountUp, decimals);
        amountDown = AmountsMath.wrapDecimals(amountDown, decimals);

        // igP multiplies a notional computed as follow:
        // V0 * user% = V0 * amount / initial(strategy) = V0 * amount / (V0/2) = amount * 2
        // (amountUp * (2 priceUp)) + (amountDown * (2 priceDown))
        marketValue_ = 2 * (amountUp * priceUp + amountDown * priceDown) / theta;
        return AmountsMath.unwrapDecimals(marketValue_, decimals);
    }
}
