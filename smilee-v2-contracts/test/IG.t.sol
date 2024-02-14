// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IDVP} from "@project/interfaces/IDVP.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {OptionStrategy} from "@project/lib/OptionStrategy.sol";
import {TimeLockedFinanceParameters, TimeLockedFinanceValues} from "@project/lib/FinanceIG.sol";
import {TimeLock, TimeLockedBool, TimeLockedUInt} from "@project/lib/TimeLock.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {DVPUtils} from "./utils/DVPUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";

contract IGTest is Test {
    using TimeLock for TimeLockedBool;
    using TimeLock for TimeLockedUInt;

    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));
    bytes constant IGPaused = bytes("Pausable: paused");
    bytes4 constant SlippedMarketValue = bytes4(keccak256("SlippedMarketValue()"));

    address baseToken;
    address sideToken;
    MockedVault vault;
    MockedRegistry registry;
    MockedIG ig;
    AddressProvider ap;
    FeeManager feeManager;

    address admin = address(0x10);
    address alice = address(0x1);
    address bob = address(0x2);

    constructor() {
        vm.warp(EpochFrequency.REF_TS);
        vm.startPrank(admin);
        ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), admin);
        registry = new MockedRegistry();
        registry.grantRole(registry.ROLE_ADMIN(), admin);
        ap.setRegistry(address(registry));
        vm.stopPrank();

        feeManager = FeeManager(ap.feeManager());

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        baseToken = vault.baseToken();
        sideToken = vault.sideToken();
    }

    function setUp() public {
        vm.startPrank(admin);
        ig = new MockedIG(address(vault), address(ap));
        ig.grantRole(ig.ROLE_ADMIN(), admin);
        ig.grantRole(ig.ROLE_EPOCH_ROLLER(), admin);
        vault.grantRole(vault.ROLE_ADMIN(), admin);

        FeeManager(ap.feeManager()).setDVPFee(
            address(ig),
            FeeManager.FeeParams(3600, 0, 0, 0, 0.0035e18, 0.125e18, 0.0015e18, 0.125e18)
        );

        registry.register(address(ig));
        MockedVault(vault).setAllowedDVP(address(ig));
        vm.stopPrank();

        ig.useFakeDeltaHedge();

        // Suppose Vault has already liquidity
        VaultUtils.addVaultDeposit(alice, 100 ether, admin, address(vault), vm);

        DVPUtils.disableOracleDelayForIG(ap, ig, admin, vm);

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();
    }

    // ToDo: review with a different vault
    // function testCantCreate() public {
    //     vm.expectRevert(AddressZero);
    //   //     new MockedIG(address(vault));
    // }

    function testCanUse() public {
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), 1, vm);

        vm.prank(alice);
        ig.mint(alice, 0, 1, 0, 0, 0.1e18, 0);
    }

    function testMint() public {
        uint256 inputAmount = 1 ether;

        // ToDo: review with premium
        // uint256 expectedPremium = ig.premium(0, OptionStrategy.CALL, inputAmount);
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        (uint256 expectedMarketValue, ) = ig.premium(0, inputAmount, 0);

        vm.prank(alice);
        ig.mint(alice, 0, inputAmount, 0, expectedMarketValue, 0.1e18, 0);

        bytes32 posId = keccak256(abi.encodePacked(alice, ig.currentStrike()));

        (uint256 amount, bool strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testMintSum() public {
        uint256 inputAmount = 1 ether;

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        (uint256 expectedMarketValue, ) = ig.premium(0, inputAmount, 0);

        vm.prank(alice);
        ig.mint(alice, 0, inputAmount, 0, expectedMarketValue, 0.1e18, 0);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        (expectedMarketValue, ) = ig.premium(0, inputAmount, 0);

        vm.prank(alice);
        ig.mint(alice, 0, inputAmount, 0, expectedMarketValue, 0.1e18, 0);

        bytes32 posId = keccak256(abi.encodePacked(alice, ig.currentStrike()));
        (uint256 amount, bool strategy, uint256 strike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(ig.currentStrike(), strike);
        assertEq(2 * inputAmount, amount);
        assertEq(ig.currentEpoch(), epoch);
    }

    function testMintAndBurn() public {
        uint256 inputAmount = 1 ether;

        //MockedIG ig = new MockedIG(address(vault));
        uint256 currEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);
        (uint256 expectedMarketValue, ) = ig.premium(strike, inputAmount, 0);
        vm.prank(alice);
        ig.mint(alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18, 0);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);
        (expectedMarketValue, ) = ig.premium(strike, inputAmount, 0);
        vm.prank(alice);
        ig.mint(alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18, 0);

        vm.prank(alice);
        (expectedMarketValue, ) = ig.payoff(currEpoch, strike, inputAmount, 0);
        vm.prank(alice);
        ig.burn(currEpoch, alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18);

        bytes32 posId = keccak256(abi.encodePacked(alice, ig.currentStrike()));

        (uint256 amount, bool strategy, uint256 pStrike, uint256 epoch) = ig.positions(posId);
        assertEq(OptionStrategy.CALL, strategy);
        assertEq(strike, pStrike);
        assertEq(inputAmount, amount);
        assertEq(currEpoch, epoch);
    }

    function testMintMultiple() public {
        bool aInputStrategy = OptionStrategy.CALL;
        bool bInputStrategy = OptionStrategy.PUT;
        uint256 inputAmount = 1;
        uint256 currEpoch = ig.currentEpoch();

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        vm.prank(alice);
        ig.mint(alice, 0, inputAmount, 0, 0, 0.1e18, 0);

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, bob, address(ig), inputAmount, vm);

        vm.prank(bob);
        ig.mint(bob, 0, 0, inputAmount, 0, 0.1e18, 0);

        uint256 strike = ig.currentStrike();

        bytes32 posId1 = keccak256(abi.encodePacked(alice, strike));
        bytes32 posId2 = keccak256(abi.encodePacked(bob, strike));

        {
            (uint256 amount1, bool strategy1, , ) = ig.positions(posId1);
            assertEq(aInputStrategy, strategy1);
            assertEq(inputAmount, amount1);
        }

        {
            (uint256 amount2, bool strategy2, , ) = ig.positions(posId2);
            assertEq(bInputStrategy, strategy2);
            assertEq(inputAmount, amount2);
        }

        vm.prank(alice);
        ig.burn(currEpoch, alice, strike, inputAmount, 0, 0, 0.1e18);
        vm.prank(bob);
        ig.burn(currEpoch, bob, strike, 0, inputAmount, 0, 0.1e18);

        {
            (uint256 amount1, , , ) = ig.positions(posId1);
            assertEq(0, amount1);
        }

        {
            (uint256 amount2, , , ) = ig.positions(posId2);
            assertEq(0, amount2);
        }
    }

    function testCantMintZero() public {
        vm.expectRevert(AmountZero);
        ig.mint(alice, 0, 0, 0, 0, 0.1e18, 0);
    }

    function testCantBurnMoreThanMinted() public {
        uint256 inputAmount = 1e18;

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        uint256 strike = ig.currentStrike();
        uint256 epoch = ig.currentEpoch();

        (uint256 expectedMarketValue, ) = ig.premium(strike, inputAmount, 0);
        vm.prank(alice);
        ig.mint(alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18, 0);

        vm.prank(alice);
        // TBD: the inputAmount cannot be used wrong as it cause an arithmetic over/underflow...
        (expectedMarketValue, ) = ig.payoff(epoch, strike, inputAmount, 0);
        vm.prank(alice);
        vm.expectRevert(CantBurnMoreThanMinted);
        ig.burn(epoch, alice, strike, inputAmount + 1e18, 0, expectedMarketValue, 0.1e18);
    }

    function testIGPaused() public {
        MarketOracle mo = MarketOracle(ap.marketOracle());
        vm.startPrank(admin);
        mo.setDelay(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, 0, true);
        vm.stopPrank();

        uint256 inputAmount = 1 ether;
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        assertEq(ig.paused(), false);

        vm.expectRevert();
        ig.changePauseState();

        vm.prank(admin);
        ig.changePauseState();
        assertEq(ig.paused(), true);

        vm.startPrank(alice);
        (uint256 expectedMarketValue, ) = ig.premium(0, inputAmount, 0);
        vm.expectRevert(IGPaused);
        ig.mint(alice, 0, inputAmount, 0, expectedMarketValue, 0.1e18, 0);
        vm.stopPrank();

        uint256 epoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        vm.prank(admin);
        ig.changePauseState();
        (expectedMarketValue, ) = ig.premium(0, inputAmount, 0);
        vm.prank(alice);
        ig.mint(alice, 0, inputAmount, 0, expectedMarketValue, 0.1e18, 0);
        vm.prank(admin);
        ig.changePauseState();
        vm.startPrank(alice);
        (expectedMarketValue, ) = ig.payoff(epoch, strike, inputAmount, 0);
        vm.expectRevert(IGPaused);
        ig.burn(epoch, alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18);
        vm.stopPrank();

        Utils.skipDay(true, vm);

        vm.prank(admin);
        vm.expectRevert(IGPaused);
        ig.rollEpoch();

        // From here on, all the IG functions should work properly
        vm.prank(admin);
        ig.changePauseState();
        assertEq(ig.paused(), false);

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();

        epoch = ig.currentEpoch();
        strike = ig.currentStrike();

        (expectedMarketValue, ) = ig.premium(0, inputAmount, 0);
        vm.startPrank(alice);
        ig.mint(alice, 0, inputAmount, 0, expectedMarketValue, 0.1e18, 0);

        (expectedMarketValue, ) = ig.payoff(epoch, strike, inputAmount, 0);
        ig.burn(epoch, alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18);
        vm.stopPrank();
    }

    function testRollEpochWhenDVPHasJumpedSomeRolls() public {
        MarketOracle mo = MarketOracle(ap.marketOracle());
        vm.startPrank(admin);
        mo.setDelay(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, 0, true);
        vm.stopPrank();

        uint256 previousEpoch = ig.currentEpoch();
        uint256 firstExpiry = EpochFrequency.nextExpiry(previousEpoch, EpochFrequency.DAILY);
        uint256 secondExpiry = EpochFrequency.nextExpiry(firstExpiry, EpochFrequency.DAILY);
        uint256 thirdExpiry = EpochFrequency.nextExpiry(secondExpiry, EpochFrequency.DAILY);
        Utils.skipDay(true, vm);
        Utils.skipDay(true, vm);

        uint256 epochNumbers = ig.getNumberOfEpochs();
        assertEq(epochNumbers, 1);

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();

        uint256 nextEpoch = ig.currentEpoch();
        uint256 lastEpoch = ig.lastRolledEpoch();
        epochNumbers = ig.getNumberOfEpochs();

        assertEq(epochNumbers, 2);
        assertEq(previousEpoch, lastEpoch);
        assertNotEq(nextEpoch, firstExpiry);
        assertNotEq(nextEpoch, secondExpiry);
        assertEq(nextEpoch, thirdExpiry);
    }

    function testSetTradeVolatilityParams() public {
        vm.expectRevert();
        ig.setTradeVolatilityTimeDecay(25e16);

        vm.expectRevert();
        ig.setTradeVolatilityUtilizationRateFactor(1.25e18);

        vm.startPrank(admin);
        ig.setTradeVolatilityUtilizationRateFactor(1.25e18);
        ig.setTradeVolatilityTimeDecay(25e16);
        vm.stopPrank();
    }

    function testMintWithSlippage() public {
        uint256 inputAmount = 1 ether;

        // ToDo: review with premium
        // uint256 expectedPremium = ig.premium(0, OptionStrategy.CALL, inputAmount);
        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);

        (uint256 expectedMarketValue, ) = ig.premium(0, inputAmount, 0);

        ig.setOptionPrice(20e18);

        vm.prank(alice);
        vm.expectRevert(SlippedMarketValue);
        ig.mint(alice, 0, inputAmount, 0, expectedMarketValue, 0.1e18, 0);
    }

    function testBurnWithSlippage() public {
        uint256 inputAmount = 1 ether;

        //MockedIG ig = new MockedIG(address(vault));
        uint256 currEpoch = ig.currentEpoch();
        uint256 strike = ig.currentStrike();

        TokenUtils.provideApprovedTokens(address(0x10), baseToken, alice, address(ig), inputAmount, vm);
        (uint256 expectedMarketValue, ) = ig.premium(strike, inputAmount, 0);
        vm.prank(alice);
        ig.mint(alice, strike, inputAmount, 0, expectedMarketValue, 0.1e18, 0);

        vm.prank(alice);
        (expectedMarketValue, ) = ig.payoff(currEpoch, strike, inputAmount, 0);

        vm.expectRevert(SlippedMarketValue);
        vm.prank(alice);
        ig.burn(currEpoch, alice, strike, inputAmount, 0, 20e18, 0.1e18);
    }

    function testSetTimeLockedParameters() public {
        // Get default values:
        TimeLockedFinanceValues memory currentValues = _getTimeLockedFinanceParameters();

        // Check default values:
        assertEq(3e18, currentValues.sigmaMultiplier);
        assertEq(2e18, currentValues.tradeVolatilityUtilizationRateFactor);
        assertEq(0.25e18, currentValues.tradeVolatilityTimeDecay);
        assertEq(0.9e18, currentValues.volatilityPriceDiscountFactor);
        assertEq(true, currentValues.useOracleImpliedVolatility);

        // Change some of the default values:
        currentValues.volatilityPriceDiscountFactor = 0.85e18;
        currentValues.useOracleImpliedVolatility = false;

        vm.prank(admin);
        ig.setParameters(currentValues);

        // They do not change until the next epoch:
        currentValues = _getTimeLockedFinanceParameters();
        assertEq(3e18, currentValues.sigmaMultiplier);
        assertEq(2e18, currentValues.tradeVolatilityUtilizationRateFactor);
        assertEq(0.25e18, currentValues.tradeVolatilityTimeDecay);
        assertEq(0.9e18, currentValues.volatilityPriceDiscountFactor);
        assertEq(true, currentValues.useOracleImpliedVolatility);

        Utils.skipDay(true, vm);

        vm.prank(admin);
        ig.rollEpoch();

        currentValues = _getTimeLockedFinanceParameters();
        assertEq(3e18, currentValues.sigmaMultiplier);
        assertEq(2e18, currentValues.tradeVolatilityUtilizationRateFactor);
        assertEq(0.25e18, currentValues.tradeVolatilityTimeDecay);
        assertEq(0.85e18, currentValues.volatilityPriceDiscountFactor);
        assertEq(false, currentValues.useOracleImpliedVolatility);
    }

    function _getTimeLockedFinanceParameters() private view returns (TimeLockedFinanceValues memory currentValues) {
        (, , , , , , TimeLockedFinanceParameters memory igParams, , ) = ig.financeParameters();
        currentValues = TimeLockedFinanceValues({
            sigmaMultiplier: igParams.sigmaMultiplier.get(),
            tradeVolatilityUtilizationRateFactor: igParams.tradeVolatilityUtilizationRateFactor.get(),
            tradeVolatilityTimeDecay: igParams.tradeVolatilityTimeDecay.get(),
            volatilityPriceDiscountFactor: igParams.volatilityPriceDiscountFactor.get(),
            useOracleImpliedVolatility: igParams.useOracleImpliedVolatility.get()
        });
    }
}
