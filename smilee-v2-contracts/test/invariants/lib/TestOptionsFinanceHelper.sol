// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FinanceParameters, VolatilityParameters, TimeLockedFinanceParameters, TimeLockedFinanceValues} from "@project/lib/FinanceIG.sol";
import {TimeLock, TimeLockedBool, TimeLockedUInt} from "@project/lib/TimeLock.sol";
import {WadTime} from "@project/lib/WadTime.sol";
import {FinanceIGPrice} from "@project/lib/FinanceIGPrice.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";
import {MockedIG} from "../../mock/MockedIG.sol";
import {Amount} from "@project/lib/Amount.sol";
import {console} from "forge-std/console.sol";

library TestOptionsFinanceHelper {
    using TimeLock for TimeLockedBool;
    using TimeLock for TimeLockedUInt;

    uint8 internal constant _BULL = 0;
    uint8 internal constant _BEAR = 1;
    uint8 internal constant _SMILE = 2;

    // S * N(d1) - K * e^(-r tau) * N(d2)
    function _optionCallPremium(
        uint256 amount,
        uint256 s,
        uint256 k,
        uint256 r,
        uint256 tau,
        uint256 n1,
        uint256 n2
    ) private pure returns (uint256) {
        uint256 p = (ud(s).mul(ud(n1))).sub(ud(k).mul(ud(FinanceIGPrice._ert(r, tau))).mul(ud(n2))).unwrap();
        return (amount * p) / k;
    }

    // K * e^(-r tau) * N(-d2) - S * N(-d1)
    function _optionPutPremium(
        uint256 amount,
        uint256 s,
        uint256 k,
        uint256 r,
        uint256 tau,
        uint256 n1,
        uint256 n2
    ) private pure returns (uint256) {
        uint256 p = (ud(k).mul(ud(FinanceIGPrice._ert(r, tau))).mul(ud(n2))).sub(ud(s).mul(ud(n1))).unwrap();
        return (amount * p) / k;
    }

    // S * (2 N(d1) - 1) - K * e^(-r tau) * (2 N(d2) - 1)
    function _optionStraddlePremium(
        uint256 amount,
        uint256 s,
        uint256 k,
        uint256 r,
        uint256 tau,
        uint256 n1,
        uint256 n2
    ) private pure returns (uint256) {
        UD60x18 p;
        {
            SD59x18 n1min1 = (ud(2e18).mul(ud(n1))).intoSD59x18().sub(sd(1e18));
            SD59x18 n2min1 = (ud(2e18).mul(ud(n2))).intoSD59x18().sub(sd(1e18));
            SD59x18 ksd = ud(k).intoSD59x18();
            SD59x18 a = ud(s).intoSD59x18().mul(n1min1);
            SD59x18 ert = ud(FinanceIGPrice._ert(r, tau)).intoSD59x18();
            SD59x18 b = ksd.mul(ert).mul(n2min1);
            p = a.sub(b).intoUD60x18();
        }
        return ud(amount).mul(p).div(ud(k)).unwrap();
    }

    // S * (N(db1) - N(-da1)) - K * e^(-r tau) * (N(db2) - N(-da2))
    function _optionStranglePremium(
        uint256 amount,
        uint256 s,
        uint256 k,
        uint256 r,
        uint256 tau,
        FinanceIGPrice.NTerms memory nas,
        FinanceIGPrice.NTerms memory nbs
    ) private pure returns (uint256) {
        // S * (N(db1) - N(-da1))
        UD60x18 p;
        {
            // N(db1) - N(-da1)
            SD59x18 n1Diff = ud(nbs.n1).intoSD59x18().sub(ud(nas.n1).intoSD59x18());
            // S * (N(db1) - N(-da1))
            SD59x18 a = ud(s).intoSD59x18().mul(n1Diff);
            // (N(db2) - N(-da2))
            SD59x18 n2Diff = ud(nbs.n2).intoSD59x18().sub(ud(nas.n2).intoSD59x18());
            // e^(-r tau)
            SD59x18 ert = ud(FinanceIGPrice._ert(r, tau)).intoSD59x18();
            SD59x18 ksd = ud(k).intoSD59x18();
            // k * e^(-r tau) * N(db2) - N(-da2)
            SD59x18 b = ksd.mul(ert).mul(n2Diff);
            p = a.sub(b).intoUD60x18();
        }
        return ud(amount).mul(p).div(ud(k)).unwrap();
    }

    /**
        @notice CALL premium option with same strike and notional of a given IG-Bull option
     */
    function _optionCallPremiumK(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (FinanceIGPrice.DTerms memory ds, , ) = FinanceIGPrice.dTerms(params);
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(ds);
        return _optionCallPremium(amount, params.s, params.k, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice CALL premium option with strike in Kb and same notional of a given IG-Bull option
     */
    function _optionCallPremiumKb(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (, , FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(params);
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(dbs);
        return _optionCallPremium(amount, params.s, params.kb, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice PUT premium option with same strike and notional of a given IG-Bear option
     */
    function _optionPutPremiumK(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (FinanceIGPrice.DTerms memory ds, , ) = FinanceIGPrice.dTerms(params);
        ds.d1 = -ds.d1;
        ds.d2 = -ds.d2;
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(ds);
        return _optionPutPremium(amount, params.s, params.k, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice PUT premium option with strike in Ka and same notional of a given IG-Bear option
     */
    function _optionPutPremiumKa(
        uint256 amount,
        FinanceIGPrice.Parameters memory params
    ) internal pure returns (uint256) {
        (, FinanceIGPrice.DTerms memory das, ) = FinanceIGPrice.dTerms(params);
        das.d1 = -das.d1;
        das.d2 = -das.d2;
        FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(das);
        return _optionPutPremium(amount, params.s, params.ka, params.r, params.tau, ns.n1, ns.n2);
    }

    /**
        @notice STRADDLE premium option with same strike and notional of a given IG-Smilee option
     */
    // function _optionStraddlePremiumK(
    //     uint256 amount,
    //     FinanceIGPrice.Parameters memory params
    // ) internal pure returns (uint256) {
    //     (FinanceIGPrice.DTerms memory ds, , ) = FinanceIGPrice.dTerms(params);
    //     FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(ds);
    //     return _optionStraddlePremium(amount, params.s, params.k, params.r, params.tau, ns.n1, ns.n2);
    // }

    /**
        @notice STRANGLE premium option with strike in Ka and Kb and same notional of a given IG-Smilee option
     */
    // function _optionStranglePremiumKaKb(
    //     uint256 amount,
    //     FinanceIGPrice.Parameters memory params
    // ) internal pure returns (uint256) {
    //     (, FinanceIGPrice.DTerms memory das, FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(params);
    //     das.d1 = -das.d1;
    //     das.d2 = -das.d2;

    //     FinanceIGPrice.NTerms memory nas = FinanceIGPrice.nTerms(das);
    //     FinanceIGPrice.NTerms memory nbs = FinanceIGPrice.nTerms(dbs);

    //     return _optionStranglePremium(amount, params.s, params.k, params.r, params.tau, nas, nbs);
    // }

    function equivalentOptionPremiums(
        uint8 strategy,
        uint256 amount,
        uint256 oraclePrice,
        uint256 riskFree,
        uint256 sigma,
        FinanceParameters memory finParams
    ) public view returns (uint256, uint256) {
        FinanceIGPrice.Parameters memory params = FinanceIGPrice.Parameters(
            riskFree, // r
            sigma,
            finParams.currentStrike,
            oraclePrice, // s
            WadTime.yearsToTimestamp(finParams.maturity), // tau
            finParams.kA,
            finParams.kB,
            finParams.theta
        );
        if (strategy == _BULL) {
            return (_optionCallPremiumK(amount, params), _optionCallPremiumKb(amount, params));
        } else if (strategy == _BEAR) {
            return (_optionPutPremiumK(amount, params), _optionPutPremiumKa(amount, params));
        } else {
            uint256 optionCallPremiumK = _optionCallPremiumK(amount, params);
            uint256 optionPutPremiumK = _optionPutPremiumK(amount, params);
            uint256 straddleK = optionCallPremiumK + optionPutPremiumK;

            uint256 optionCallPremiumKb = _optionCallPremiumKb(amount, params);
            uint256 optionPutPremiumKa = _optionPutPremiumKa(amount, params);
            uint256 strangleKaKb = optionCallPremiumKb + optionPutPremiumKa;

            return (straddleK, strangleKaKb);
        }
    }

    function getFinanceParameters(MockedIG ig) internal view returns (FinanceParameters memory fp) {
        (
            uint256 maturity,
            uint256 currentStrike,
            Amount memory initialLiquidity,
            uint256 kA,
            uint256 kB,
            uint256 theta,
            TimeLockedFinanceParameters memory timeLocked,
            uint256 sigmaZero,
            VolatilityParameters memory internalVolatilityParameters
        ) = ig.financeParameters();
        fp = FinanceParameters(
            maturity,
            currentStrike,
            initialLiquidity,
            kA,
            kB,
            theta,
            timeLocked,
            sigmaZero,
            internalVolatilityParameters
        );
    }

    function getTimeLockedFinanceParameters(
        MockedIG ig
    ) internal view returns (TimeLockedFinanceValues memory currentValues) {
        (, , , , , , TimeLockedFinanceParameters memory igParams, , ) = ig.financeParameters();
        currentValues = TimeLockedFinanceValues({
            sigmaMultiplier: igParams.sigmaMultiplier.get(),
            tradeVolatilityUtilizationRateFactor: igParams.tradeVolatilityUtilizationRateFactor.get(),
            tradeVolatilityTimeDecay: igParams.tradeVolatilityTimeDecay.get(),
            volatilityPriceDiscountFactor: igParams.volatilityPriceDiscountFactor.get(),
            useOracleImpliedVolatility: igParams.useOracleImpliedVolatility.get()
        });
    }

    /**
        P = V0 / θ * F
        F = {
            S / √(K Ka) - S / √(K Kb)             if (S < Ka)
            2 √(S / K) - √(Ka / K) - S / √(K Kb)  if (Ka < S < Kb)
            √(Kb / K) - √(Ka / K)                 if (S > Kb)
        }
     */
    function vaultPayoff(
        uint256 k1, // final price
        uint256 k0, // starting price
        uint256 kA,
        uint256 kB,
        uint256 theta
    ) public pure returns (uint256) {

        UD60x18 f;
        if (k1 < kA) {
            UD60x18 k0kartd = (ud(k0).mul(ud(kA))).sqrt();
            UD60x18 k0kbrtd = (ud(k0).mul(ud(kB))).sqrt();
            f = ud(k1).div(k0kartd).sub(ud(k1).div(k0kbrtd));
        } else if (k1 > kB) {
            UD60x18 kadivk0rtd = (ud(kA).div(ud(k0))).sqrt();
            UD60x18 kbdivk0rtd = (ud(kB).div(ud(k0))).sqrt();
            f = kbdivk0rtd.sub(kadivk0rtd);
        } else {
            UD60x18 k1divk0rtd = (ud(k1).div(ud(k0))).sqrt();
            UD60x18 kadivk0rtd = (ud(kA).div(ud(k0))).sqrt();
            UD60x18 k0kbrtd = (ud(k0).mul(ud(kB))).sqrt();
            f = ud(2e18).mul(k1divk0rtd).sub(kadivk0rtd).sub(ud(k1).div(k0kbrtd));
        }
        return  f.div(ud(theta)).unwrap();
    }

    /**
        LP token value formulas
     */
    function lpValue(FinanceIGPrice.Parameters memory params) public pure returns (uint256) {
        (, FinanceIGPrice.DTerms memory das, FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(params);
        FinanceIGPrice.NTerms memory nas = FinanceIGPrice.nTerms(das);
        FinanceIGPrice.NTerms memory nbs = FinanceIGPrice.nTerms(dbs);

        uint256 ert = FinanceIGPrice._ert(params.r, params.tau); // e^-(r τ)
        UD60x18 v1 = _lpV1(params, nas.n1);
        UD60x18 v5 = _lpV5(params, nbs.n2, ert);
        UD60x18 v2 = _lpV2(params, nas.n2, ert);
        UD60x18 v3 = _lpV3(params, nas.n3, nbs.n3);
        UD60x18 v4 = _lpV4(params, nbs.n1);

        return (v1.add(v5).sub(v2).sub(v3).sub(v4)).div(ud(params.teta)).unwrap();
    }

    // S / √(K Ka) * (1 - N(d1a))
    function _lpV1(FinanceIGPrice.Parameters memory params, uint256 n1) private pure returns (UD60x18) {
        // S / √(K Ka)
        UD60x18 sDivKkartd = ud(params.s).div((ud(params.k).mul(ud(params.ka))).sqrt());
        return sDivKkartd.mul(ud(1e18).sub(ud(n1)));
    }

    // S / √(K Kb) * (1 - N(d1b))
    function _lpV4(FinanceIGPrice.Parameters memory params, uint256 n1) private pure returns (UD60x18) {
        // S / √(K Kb)
        UD60x18 sDivKkbrtd = ud(params.s).div((ud(params.k).mul(ud(params.kb))).sqrt());
        return sDivKkbrtd.mul(ud(1e18).sub(ud(n1)));
    }

    // √(Ka / K) * erτ * (N(d2a))
    function _lpV2(FinanceIGPrice.Parameters memory params, uint256 n2, uint256 ert) private pure returns (UD60x18) {
        // √(Ka / K)
        UD60x18 kadivkRtd = (ud(params.ka).div(ud(params.k))).sqrt();
        return kadivkRtd.mul(ud(ert)).mul(ud(n2));
    }

    // √(Kb / K) * erτ * (N(d2b))
    function _lpV5(FinanceIGPrice.Parameters memory params, uint256 n2, uint256 ert) private pure returns (UD60x18) {
        // √(Kb / K)
        UD60x18 kbdivkRtd = (ud(params.kb).div(ud(params.k))).sqrt();
        return kbdivkRtd.mul(ud(ert)).mul(ud(n2));
    }

    // 2 √(S / K) * e^-(r / 2 + σ^2 / 8)τ * (N(d3b) - N(d3a))
    function _lpV3(FinanceIGPrice.Parameters memory params, uint256 n3a, uint256 n3b) private pure returns (UD60x18) {
        // e^-(r / 2 + σ^2 / 8)τ
        UD60x18 er2sig8 = ud(FinanceIGPrice.er2sig8(params.r, params.sigma, params.tau));
        // √(S / K)
        UD60x18 sdivkRtd = (ud(params.s).div(ud(params.k))).sqrt();
        return ud(2e18).mul(sdivkRtd).mul(er2sig8).mul(ud(n3b).sub(ud(n3a)));
    }

}
