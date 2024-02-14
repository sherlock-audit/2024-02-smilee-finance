// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Gaussian} from "@solstat/Gaussian.sol";
import {AmountsMath} from "@project/lib/AmountsMath.sol";
import {FinanceIG} from "@project/lib/FinanceIG.sol";
import {FinanceIGDelta} from "@project/lib/FinanceIGDelta.sol";
import {FinanceIGPayoff} from "@project/lib/FinanceIGPayoff.sol";
import {FinanceIGPrice} from "@project/lib/FinanceIGPrice.sol";
import {WadTime} from "@project/lib/WadTime.sol";
import {ud} from "@prb/math/UD60x18.sol";

contract FinanceLibJsonTest is Test {
    using AmountsMath for uint256;
    using stdJson for string;

    struct DeltaComponents {
        int256 igDBear;
        int256 igDBull;
        int256 x;
    }

    struct PriceComponents {
        FinanceIGPrice.DTerms das;
        FinanceIGPrice.DTerms dbs;
        FinanceIGPrice.DTerms ds;
        uint256 igP;
        uint256 pBear;
        uint256 pBear1;
        uint256 pBear2;
        uint256 pBear3;
        uint256 pBear4;
        uint256 pBear5;
        uint256 pBull;
        uint256 pBull1;
        uint256 pBull2;
        uint256 pBull3;
        uint256 pBull4;
        uint256 pBull5;
    }

    struct Payoff {
        uint256 igBear;
        uint256 igBull;
    }

    struct TestCase {
        DeltaComponents delta;
        FinanceIGDelta.Parameters deltaParams;
        Payoff payoff;
        PriceComponents price;
        FinanceIGPrice.Parameters priceParams;
        uint256 priceToken;
        uint256 tau;
        uint256 v0;
    }

    struct TestCaseJson {
        DeltaComponents delta;
        Payoff payoff;
        PriceComponents price;
        uint256 priceToken;
        uint256 tau;
    }

    struct LiquidityRange {
        // inputs
        uint256 strike;
        uint256 volatility;
        uint256 volatilityMultiplier;
        uint256 yearsOfMaturity;
        // results
        uint256 kA;
        uint256 kB;
    }

    struct TradeVolatility {
        // inputs
        uint256 baselineVolatility;
        uint256 utilizationRateFactor;
        uint256 timeDecay;
        uint256 utilizationRate;
        uint256 maturity;
        uint256 initialTime;
        // result
        uint256 volatility;
    }

    struct Constants {
        uint256 k;
        uint256 ka;
        uint256 kb;
        uint256 r;
        uint256 sigma;
        uint256 v0;
    }

    struct Scenario {
        Constants constants;
        TestCaseJson[] testCases;
    }

    mapping(uint256 => TestCase) testCases;
    mapping(uint256 => uint256) indexes;
    uint256 scenariosNumber = 0;

    /**
        @dev Accepted delta on comparisons (up to 5e-6)
        This is mainly due to limitations of `Gaussian.cdf()` computation error.
     */
    uint256 constant ERR = 1e12;

    constructor() {}

    // TBD: Move all in the constructor?
    function setUp() public {
        string memory json = _readJson("financials");
        Scenario[] memory scenarios_ = _readScenariosFromJson(json);
        uint256 counter = 0;
        for (uint i = 0; i < scenarios_.length; i++) {
            Scenario memory scenario = scenarios_[i];
            uint256 theta = FinanceIGPrice._teta(scenario.constants.k, scenario.constants.ka, scenario.constants.kb);
            for (uint j = 0; j < scenario.testCases.length; j++) {
                // Avoid stack too deep;
                uint256 counterStack = counter++;
                TestCaseJson memory t = scenario.testCases[j];
                uint256 tau = WadTime.nYears(t.tau); // ToDo: review
                FinanceIGDelta.Parameters memory deltaParams = FinanceIGDelta.Parameters(scenario.constants.k, scenario.constants.ka, scenario.constants.kb, t.priceToken, theta);
                FinanceIGPrice.Parameters memory priceParams = FinanceIGPrice.Parameters(scenario.constants.r, scenario.constants.sigma, scenario.constants.k, t.priceToken, tau, scenario.constants.ka, scenario.constants.kb, theta);
                testCases[counterStack] = TestCase(t.delta, deltaParams, t.payoff, t.price, priceParams, t.priceToken, tau, scenario.constants.v0);
            }
            indexes[i] = counter;
        }
    }

    function testDeltas() public {
        uint256 D_ERR = 1e9;
        uint256 index = 0;
        for (uint s = 0; s < scenariosNumber; s++) {
            uint256 indexScenarioMax = indexes[s];
            for (uint256 i = index; i < indexScenarioMax; i++) {
                (int256 igDBull, int256 igDBear) = FinanceIGDelta.deltaHedgePercentages(testCases[i].deltaParams);

                assertApproxEqAbs(testCases[i].delta.igDBull, (int256(testCases[i].v0) * igDBull) / 1e18, D_ERR);
                assertApproxEqAbs(testCases[i].delta.igDBear, (int256(testCases[i].v0) * igDBear) / 1e18, D_ERR);
            }
            index = indexScenarioMax;
        }
    }

    function testTermsDs() public {
        uint256 index = 0;
        for (uint s = 0; s < scenariosNumber; s++) {
            uint256 indexScenarioMax = indexes[s];
            for (uint256 i = index; i < indexScenarioMax; i++) {
                (FinanceIGPrice.DTerms memory ds, FinanceIGPrice.DTerms memory das, FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(testCases[i].priceParams);

                assertApproxEqAbs(testCases[i].price.ds.d1, ds.d1, ERR);
                assertApproxEqAbs(testCases[i].price.ds.d2, ds.d2, ERR);
                assertApproxEqAbs(testCases[i].price.ds.d3, ds.d3, ERR);

                assertApproxEqAbs(testCases[i].price.das.d1, das.d1, ERR);
                assertApproxEqAbs(testCases[i].price.das.d2, das.d2, ERR);
                assertApproxEqAbs(testCases[i].price.das.d3, das.d3, ERR);

                assertApproxEqAbs(testCases[i].price.dbs.d1, dbs.d1, ERR);
                assertApproxEqAbs(testCases[i].price.dbs.d2, dbs.d2, ERR);
                assertApproxEqAbs(testCases[i].price.dbs.d3, dbs.d3, ERR);
            }
            index = indexScenarioMax;
        }
    }

    function testTermsPs() public {
        uint256 index = 0;
        for (uint s = 0; s < scenariosNumber; s++) {
            uint256 indexScenarioMax = indexes[s];
            for (uint256 i = index; i < indexScenarioMax; i++) {
                (FinanceIGPrice.DTerms memory ds, FinanceIGPrice.DTerms memory das, FinanceIGPrice.DTerms memory dbs) = FinanceIGPrice.dTerms(testCases[i].priceParams);
                FinanceIGPrice.NTerms memory ns = FinanceIGPrice.nTerms(ds);
                FinanceIGPrice.NTerms memory nas = FinanceIGPrice.nTerms(das);
                FinanceIGPrice.NTerms memory nbs = FinanceIGPrice.nTerms(dbs);

                uint256 ert = FinanceIGPrice._ert(testCases[i].priceParams.r, testCases[i].priceParams.tau);
                uint256 sdivk = (testCases[i].priceParams.s).wdiv(testCases[i].priceParams.k);
                uint256 theta= testCases[i].priceParams.teta;

                {
                    FinanceIGPrice.PriceParts memory ps = FinanceIGPrice.pBullParts(testCases[i].priceParams, ert, sdivk, ns, nbs);
                    assertApproxEqAbs(testCases[i].price.pBull1, ps.p1 * 1e18 / theta , ERR);
                    assertApproxEqAbs(testCases[i].price.pBull2, ps.p2 * 1e18 / theta , ERR);
                    assertApproxEqAbs(testCases[i].price.pBull3, ps.p3 * 1e18 / theta , ERR);
                    assertApproxEqAbs(testCases[i].price.pBull4, ps.p4 * 1e18 / theta , ERR);
                    assertApproxEqAbs(testCases[i].price.pBull5, ps.p5 * 1e18 / theta , ERR);
                }

                {
                    FinanceIGPrice.PriceParts memory ps = FinanceIGPrice.pBearParts(testCases[i].priceParams, ert, sdivk, ns, nas);
                    assertApproxEqAbs(testCases[i].price.pBear1, ps.p1 * 1e18 / theta , ERR);
                    assertApproxEqAbs(testCases[i].price.pBear2, ps.p2 * 1e18 / theta , ERR);
                    assertApproxEqAbs(testCases[i].price.pBear3, ps.p3 * 1e18 / theta , ERR);
                    assertApproxEqAbs(testCases[i].price.pBear4, ps.p4 * 1e18 / theta , ERR);
                    assertApproxEqAbs(testCases[i].price.pBear5, ps.p5 * 1e18 / theta , ERR);
                }
            }
            index = indexScenarioMax;
        }
    }

    function testPrices() public {
        uint256 index = 0;
        for (uint s = 0; s < scenariosNumber; s++) {
            uint256 indexScenarioMax = indexes[s];
            for (uint256 i = index; i < indexScenarioMax; i++) {
                (uint256 pBull, uint256 pBear) = FinanceIGPrice.igPrices(testCases[i].priceParams);
                assertApproxEqAbs(testCases[i].price.pBull, testCases[i].v0.wmul(pBull).wdiv(testCases[i].priceParams.teta), 6e16);
                assertApproxEqAbs(testCases[i].price.pBear, testCases[i].v0.wmul(pBear).wdiv(testCases[i].priceParams.teta), 6e16);
            }
            index = indexScenarioMax;
        }
    }

    function testPayoff() public {
        uint256 index = 0;
        for (uint s = 0; s < scenariosNumber; s++) {
            uint256 indexScenarioMax = indexes[s];
            for (uint256 i = index; i < indexScenarioMax; i++) {
                (uint256 poBull, uint256 poBear) = FinanceIGPayoff.igPayoffPerc(testCases[i].priceParams.s, testCases[i].priceParams.k, testCases[i].priceParams.ka, testCases[i].priceParams.kb, testCases[i].priceParams.teta);
                assertApproxEqAbs(testCases[i].payoff.igBull, testCases[i].v0.wmul(poBull), ERR);
                assertApproxEqAbs(testCases[i].payoff.igBear, testCases[i].v0.wmul(poBear), ERR);
            }
            index = indexScenarioMax;
        }
    }

    function testLiquidityRange() public {
        uint256 volatility = 5e17;
        uint256 volatilityMultiplier = 2e18;
        uint256 dailyMaturity = AmountsMath.wrap(1) / 365;

        // Fixed maturity, change strike price:
        _checkLiquidityRange(LiquidityRange(1800e18, volatility, volatilityMultiplier, dailyMaturity, 1708206983329e9, 1896725649538e9));
        _checkLiquidityRange(LiquidityRange(1900e18, volatility, volatilityMultiplier, dailyMaturity, 1803107371292e9, 2002099296734e9));
        _checkLiquidityRange(LiquidityRange(1910e18, volatility, volatilityMultiplier, dailyMaturity, 1812597410088e9, 2012636661454e9));
        _checkLiquidityRange(LiquidityRange(1950e18, volatility, volatilityMultiplier, dailyMaturity, 1850557565273e9, 2054786120333e9));
        _checkLiquidityRange(LiquidityRange(2200e18, volatility, volatilityMultiplier, dailyMaturity, 2087808535180e9, 2318220238324e9));
        _checkLiquidityRange(LiquidityRange(3800e18, volatility, volatilityMultiplier, dailyMaturity, 3606214742584e9, 4004198593469e9));
        // Fixed strike price, change maturity:
        _checkLiquidityRange(LiquidityRange(1900e18, volatility, volatilityMultiplier, dailyMaturity * 7, 1654285069345e9, 2182211558876e9));
        _checkLiquidityRange(LiquidityRange(1900e18, volatility, volatilityMultiplier, dailyMaturity * 21, 1494797747280e9, 2415042440737e9));
        _checkLiquidityRange(LiquidityRange(1900e18, volatility, volatilityMultiplier, dailyMaturity * 30, 1426412850588e9, 2530824086807e9));

        // ToDo: check corner cases
    }

    function _checkLiquidityRange(LiquidityRange memory params) private {
        (uint256 kA, uint256 kB) = FinanceIGPrice.liquidityRange(FinanceIGPrice.LiquidityRangeParams(params.strike, params.volatility, params.volatilityMultiplier, params.yearsOfMaturity));
        uint256 maxError = 1e9;
        assertApproxEqAbs(params.kA, kA, maxError);
        assertApproxEqAbs(params.kB, kB, maxError);
    }

    function testTradeVolatility() public {
        uint256 baselineVolatility = 70e16; // 0.7 Wad == 70 %
        uint256 utilizationRateFactor = 2e18; // 2 Wad
        uint256 timeDecay = 25e16; // 0.25 Wad
        uint256 utilizationRate = 50e16; // 0.5 Wad == 50 %

        // Test time decay effect:
        uint256 initialTime = 0;
        uint256 maturity = initialTime + 7 days;
        uint256 time = initialTime;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 787500e12));
        time = time + 1 days;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 759375e12));
        time = time + 1 days;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 731250e12));
        time = time + 1 days;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 703125e12));
        time = time + 1 days;
        vm.warp(time);
        _checkTradeVolatility(TradeVolatility(baselineVolatility, utilizationRateFactor, timeDecay, utilizationRate, maturity, initialTime, 675000e12));

        // ToDo: check corner cases
    }

    function testDeltaHedgeAmount() public {
        FinanceIGDelta.DeltaHedgeParameters memory input = FinanceIGDelta.DeltaHedgeParameters({
            igDBull: 0.000067543642961551e18,
            igDBear: 0,
            baseTokenDecimals: 18,
            sideTokenDecimals: 18,
            initialLiquidityBull: 50_000e18,
            initialLiquidityBear: 50_000e18,
            availableLiquidityBull: 50_000e18,
            availableLiquidityBear: 50_000e18,
            sideTokensAmount: 26.31578947368420e18,
            notionalUp: 10_000e18,
            notionalDown: 0e18,
            strike: 1_900e18,
            theta: 0.197303740911534e18,
            kb: 2_338.6674832963900e18
        });
        int256 output = FinanceIGDelta.deltaHedgeAmount(input);
        assertApproxEqAbs(5.40349143692413162e18, output, 1e9);
    }

    function testSigmaZero() public {
        uint256 n = 2e18;
        uint256 theta = 0.25e18;
        uint256 sigmaZero_ = 0.5e18;

        assertApproxEqAbs(0.66650391e18, FinanceIG.sigmaZero(ud(3e18).div(ud(4e18)).unwrap(), n, theta, sigmaZero_), 1e10);
        assertApproxEqAbs(0.94711697e18, FinanceIG.sigmaZero(ud(3.1e18).div(ud(3.2e18)).unwrap(), n, theta, sigmaZero_), 1e10);
        assertApproxEqAbs(0.86323124e18, FinanceIG.sigmaZero(ud(3.2e18).div(ud(3.5e18)).unwrap(), n, theta, sigmaZero_), 1e10);
        assertApproxEqAbs(0.71322389e18, FinanceIG.sigmaZero(ud(3.5e18).div(ud(4.4e18)).unwrap(), n, theta, sigmaZero_), 1e10);
        assertApproxEqAbs(0.75646219e18, FinanceIG.sigmaZero(ud(4e18).div(ud(4.8e18)).unwrap(), n, theta, sigmaZero_), 1e10);
        assertApproxEqAbs(0.81866836e18, FinanceIG.sigmaZero(ud(4.5e18).div(ud(5.1e18)).unwrap(), n, theta, sigmaZero_), 1e10);
    }

    function _checkTradeVolatility(TradeVolatility memory params) private {
        uint256 volatility = FinanceIGPrice.tradeVolatility(FinanceIGPrice.TradeVolatilityParams(params.baselineVolatility, params.utilizationRateFactor, params.timeDecay, params.utilizationRate, params.maturity, params.initialTime));
        uint256 maxError = 1e11;
        assertApproxEqAbs(params.volatility, volatility, maxError);
    }

    function _readJson(string memory filename) private view returns (string memory) {
        string memory directory = string.concat(vm.projectRoot(), "/test/resources/");
        string memory file = string.concat(filename, ".json");
        string memory path = string.concat(directory, file);

        return vm.readFile(path);
    }

    function _readScenariosFromJson(string memory json) private returns (Scenario[] memory scenarios_) {
        scenariosNumber = json.readUint("$.scenariosNum");
        scenarios_ = new Scenario[](scenariosNumber);
        bytes memory elBytes;
        for (uint i = 0; i < scenariosNumber; i++) {
            string memory scenarioJsonPath = string.concat("$.scenarios[", Strings.toString(i), "]");
            elBytes = json.parseRaw(string.concat(scenarioJsonPath, ".constants"));
            Constants memory c = abi.decode(elBytes, (Constants));
            elBytes = json.parseRaw(string.concat(scenarioJsonPath, ".expected"));
            uint256 testCasesNumber = json.readUint(string.concat(scenarioJsonPath, ".testCasesNumber"));
            TestCaseJson[] memory testCasesObj = new TestCaseJson[](testCasesNumber);
            for (uint j = 0; j < testCasesNumber; j++) {
                string memory testCasesJsonPath = string.concat(scenarioJsonPath, ".testCases[", Strings.toString(j), "]");
                elBytes = json.parseRaw(testCasesJsonPath);
                TestCaseJson memory t = abi.decode(elBytes, (TestCaseJson));
                testCasesObj[j] = t;
            }
            Scenario memory s = Scenario(c, testCasesObj);
            scenarios_[i] = s;
        }
    }
}
