// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {Registry} from "@project/periphery/Registry.sol";
import {Factory} from "./utils/Factory.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";

contract FeeManagerTest is Test {
    FeeManager _feeManager;
    address _admin = address(0x1);
    address _fakeDVP;

    constructor() {
        vm.startPrank(_admin);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), _admin);
        vm.stopPrank();

        address baseToken = TokenUtils.create("USDC", 6, ap, _admin, vm);
        address sideToken = TokenUtils.create("ETH", 18, ap, _admin, vm);

        vm.startPrank(_admin);
        Factory factory = new Factory(address(ap));
        Registry registry = new Registry();
        registry.grantRole(registry.ROLE_ADMIN(), _admin);
        registry.grantRole(registry.ROLE_ADMIN(), address(factory));
        ap.setRegistry(address(registry));

        _fakeDVP = factory.createIGMarket(baseToken, sideToken, 86400);
        vm.stopPrank();
    }

    function setUp() public {
        vm.startPrank(_admin);
        _feeManager = new FeeManager(0);
        _feeManager.grantRole(_feeManager.ROLE_ADMIN(), _admin);
        vm.stopPrank();
    }

    function testFeeManagerSetter(
        uint256 timeToExpiryThreshold,
        uint256 minFeeBeforeThreshold,
        uint256 minFeeAfterThreshold,
        uint256 successFeeTier,
        uint256 feePercentage,
        uint256 capPercertage,
        uint256 mFeePercentage,
        uint256 mCapPercentage
    ) public {
        vm.startPrank(_admin);

        vm.assume(timeToExpiryThreshold > 0);
        vm.assume(minFeeBeforeThreshold < 0.5e6);
        vm.assume(minFeeAfterThreshold < 0.5e6);
        vm.assume(successFeeTier < 0.1e18);
        vm.assume(feePercentage < 0.05e18);
        vm.assume(capPercertage < 0.3e18);
        vm.assume(mFeePercentage < 0.05e18);
        vm.assume(mCapPercentage < 0.3e18);

        FeeManager.FeeParams memory params = FeeManager.FeeParams(
            timeToExpiryThreshold,
            minFeeBeforeThreshold,
            minFeeAfterThreshold,
            successFeeTier,
            feePercentage,
            capPercertage,
            mFeePercentage,
            mCapPercentage
        );

        _feeManager.setDVPFee(_fakeDVP, params);

        {
            (
                uint256 timeToExpiryThresholdCheck,
                uint256 minFeeBeforeThresholdCheck,
                uint256 minFeeAfterThresholdCheck,
                uint256 successFeeTierCheck,
                uint256 feePercentageCheck,
                uint256 capPercentageCheck,
                uint256 maturityFeePercentageCheck,
                uint256 maturityCapPercentageCheck
            ) = _feeManager.dvpsFeeParams(_fakeDVP);

            assertEq(params.timeToExpiryThreshold, timeToExpiryThresholdCheck);
            assertEq(params.minFeeBeforeTimeThreshold, minFeeBeforeThresholdCheck);
            assertEq(params.minFeeAfterTimeThreshold, minFeeAfterThresholdCheck);
            assertEq(params.successFeeTier, successFeeTierCheck);
            assertEq(params.feePercentage, feePercentageCheck);
            assertEq(params.capPercentage, capPercentageCheck);
            assertEq(params.maturityFeePercentage, maturityFeePercentageCheck);
            assertEq(params.maturityCapPercentage, maturityCapPercentageCheck);
        }

        vm.stopPrank();
    }

    function testTradeBuyFee() public {
        FeeManager.FeeParams memory params = FeeManager.FeeParams({
            timeToExpiryThreshold: 3600, // 1H
            minFeeBeforeTimeThreshold: 0.3e6,
            minFeeAfterTimeThreshold: 0.2e6,
            successFeeTier: 0.5e18,
            feePercentage: 0.05e18, // Fee Applied to Notional
            capPercentage: 0.01e18, // Fee Applied to Premium
            maturityFeePercentage: 0.025e18,
            maturityCapPercentage: 0.05e18
        });

        vm.prank(_admin);
        _feeManager.setDVPFee(_fakeDVP, params);

        // Check Notional Fee
        uint256 fakeEpochBeforeTreeshold = block.timestamp + 7200;

        uint256 premium = 200e6;
        uint256 amountUp = 30e6;
        uint256 amountDown = 5e6;

        uint256 expectedFee = 1.75e6;

        (uint256 fee, uint256 minFee) = _feeManager.tradeBuyFee(
            _fakeDVP,
            fakeEpochBeforeTreeshold,
            amountUp + amountDown,
            premium,
            6
        );
        assertEq(expectedFee + params.minFeeBeforeTimeThreshold, fee);
        assertEq(params.minFeeBeforeTimeThreshold, minFee);

        // Check Premium Fee
        premium = 0.2e6;
        // amountUp = 30e6;
        // amountDown = 5e6;

        expectedFee = 0.01e6;

        (fee, minFee) = _feeManager.tradeBuyFee(_fakeDVP, fakeEpochBeforeTreeshold, premium, amountUp + amountDown, 6);
        assertEq(expectedFee + params.minFeeBeforeTimeThreshold, fee);
        assertEq(params.minFeeBeforeTimeThreshold, minFee);

        // Check Min Fee Before Threshold
        premium = 0.01e6;
        // amountUp = 30e6;
        // amountDown = 5e6;

        expectedFee = 0.0001e6; // min(35 * 0.05, 0.01 * 0.01) = min(1.75, 0.0001) = 0.0001

        (fee, minFee) = _feeManager.tradeBuyFee(_fakeDVP, fakeEpochBeforeTreeshold, amountUp + amountDown, premium, 6);
        assertEq(expectedFee + params.minFeeBeforeTimeThreshold, fee);
        assertEq(params.minFeeBeforeTimeThreshold, minFee);

        // Check Min Fee After Threshold
        uint256 fakeEpochAfterTreeshold = block.timestamp + 3599;
        // premium = 0.01e6;
        // amountUp = 30e6;
        // amountDown = 5e6;
        // expectedFee = 0.0001e6; // min(35 * 0.05, 0.01 * 0.01) = min(1.75, 0.0001) = 0.0001

        (fee, minFee) = _feeManager.tradeBuyFee(_fakeDVP, fakeEpochAfterTreeshold, amountUp + amountDown, premium, 6);
        assertEq(expectedFee + params.minFeeAfterTimeThreshold, fee);
        assertEq(params.minFeeAfterTimeThreshold, minFee);
    }

    function testTradeSellFee() public {

        // Since block.timestamp starts from 1, set 1000 to avoid underlow on simulating an expired epoch
        vm.warp(1000);
        
        uint256 vaultMinFee = 0.2e6;
        // Ignore timeToExpiry currently, so we set minFeeBeforeTimeThreshold and minFeeAfterTimeThreshold with the same value. 
        // The thresholded fees are now applied both to buy or sell.
        FeeManager.FeeParams memory params = FeeManager.FeeParams({
            timeToExpiryThreshold: 3600, // 1H
            minFeeBeforeTimeThreshold: vaultMinFee,
            minFeeAfterTimeThreshold: vaultMinFee,
            successFeeTier: 0.05e18,
            feePercentage: 0.05e18, // Fee Applied to Notional
            capPercentage: 0.01e18, // Fee Applied to Premium
            maturityFeePercentage: 0.025e18,
            maturityCapPercentage: 0.005e18
        });

        vm.prank(_admin);
        _feeManager.setDVPFee(_fakeDVP, params);

        // Check Sell Without Profit No Maturity Reached (Premium based fee)
        uint256 premium = 20e6;
        uint256 initialPaidPremium = 30e6;
        uint256 amountUp = 3000e6;
        uint256 amountDown = 5e6;

        uint256 expectedFee = 0.2e6 + vaultMinFee; // min(3005 * 0.05, 20 * 0.01) = min(150.25, 0.2) = 0.2 + 0.4 minFee = 0.5
        // uint256 expectedMinFee = 5e6;

        (uint256 fee, uint256 minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp + 100, // anytime in the future
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            6
        );
        assertEq(expectedFee, fee);
        assertEq(vaultMinFee, minFee);

        // Check Sell Without Profit Maturity Reached (Premium based fee)
        premium = 20e6;
        initialPaidPremium = 30e6;
        amountUp = 3000e6;
        amountDown = 5e6;

        expectedFee = 0.1e6;

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp - 100, // anytime in the past
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            6
        );
        assertEq(expectedFee, fee);
        assertEq(0, minFee);

        // Check Sell Without Profit No Maturity Reached (Notional based fee)
        premium = 200e6;
        initialPaidPremium = 300e6;
        amountUp = 30e6;
        amountDown = 5e6;

        expectedFee = 1.75e6 + vaultMinFee; // min(35 * 0.05, 200 * 0.01) = min(1.75, 2) = 1.75

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp + 100, // anytime in the future
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            6
        );
        assertEq(expectedFee, fee);
        assertEq(vaultMinFee, minFee);

        // Check Sell Without Profit Maturity Reached (Notional based fee)
        premium = 200e6;
        initialPaidPremium = 300e6;
        amountUp = 30e6;
        amountDown = 5e6;

        expectedFee = 0.875e6;

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp - 100, // anytime in the past
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            6
        );
        assertEq(expectedFee, fee);
        assertEq(0, minFee);

        // Check Sell With Profit No Maturity Reached (Premium based fee)
        premium = 20e6;
        initialPaidPremium = 10e6;
        amountUp = 3000e6;
        amountDown = 5e6;

        // successFee = (20 - 10) * 0.05 = 0.5
        expectedFee = 0.2e6 + 0.5e6 + vaultMinFee; // min(3005 * 0.05, 20 * 0.01) = min(150.25, 0.2) = 0.2

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp + 100, // anytime in the future
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            6
        );
        assertEq(expectedFee, fee);
        assertEq(vaultMinFee, minFee);

        // Check Sell With Profit Maturity Reached (Premium based fee)
        premium = 20e6;
        initialPaidPremium = 10e6;
        amountUp = 3000e6;
        amountDown = 5e6;

        expectedFee = 0.6e6; // 0.1 + 0.5

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp - 100, // anytime in the past
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            6
        );
        assertEq(expectedFee, fee);
        assertEq(0, minFee);

        // Check Sell With Profit No Maturity Reached (Notional based fee)
        premium = 200e6;
        initialPaidPremium = 100e6;
        amountUp = 30e6;
        amountDown = 5e6;

        // successFee = (200 - 100) * 0.05 = 5
        // tradeFee = min(35 * 0.05, 200 * 0.01) = min(1.75, 2) = 1.75
        expectedFee = 1.75e6 + 5e6 + vaultMinFee;

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp + 100, // anytime in the future
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            6
        );
        assertEq(expectedFee, fee);
        assertEq(vaultMinFee, minFee);

        // Check Sell With Profit Maturity Reached (Notional based fee)
        premium = 200e6;
        initialPaidPremium = 100e6;
        amountUp = 30e6;
        amountDown = 5e6;

        expectedFee = 5.875e6;

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp - 100, // anytime in the past
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            6
        );
        assertEq(expectedFee, fee);
        assertEq(0, minFee);

        // Check Premium 0 No Maturity Reached
        premium = 0;
        initialPaidPremium = 100e6;
        amountUp = 30e6;
        amountDown = 5e6;

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp + 100, // anytime in the future
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            18
        );
        assertEq(vaultMinFee, fee);
        assertEq(vaultMinFee, minFee);

        // Check Premium 0 Maturity Reached

        premium = 0;
        initialPaidPremium = 100e6;
        amountUp = 30e6;
        amountDown = 5e6;

        (fee, minFee) = _feeManager.tradeSellFee(
            _fakeDVP,
            block.timestamp - 100, // anytime in the past
            amountUp + amountDown,
            premium,
            initialPaidPremium,
            18
        );
        assertEq(0, fee);
        assertEq(0, minFee);
    }
}
