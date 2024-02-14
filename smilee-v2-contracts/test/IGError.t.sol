// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "@project/interfaces/IPositionManager.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {OptionStrategy} from "@project/lib/OptionStrategy.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {Vault} from "@project/Vault.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {MockedVault} from "./mock/MockedVault.sol";

/**
    @title Test case for underlying asset going to zero
    @dev This should never happen, still we need to test shares value goes to zero, users deposits can be rescued and
         new deposits are not allowed
 */
contract IGErrorTest is Test {

    address admin = address(0x1);

    // User of Vault
    address alice = address(0x2);

    //User of DVP
    address charlie = address(0x4);

    AddressProvider ap;
    TestnetToken baseToken;
    TestnetToken sideToken;
    FeeManager feeManager;
    TestnetPriceOracle po;

    MockedRegistry registry;

    MockedVault vault;
    MockedIG ig;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.startPrank(admin);
        ap = new AddressProvider(0);
        registry = new MockedRegistry();
        ap.grantRole(ap.ROLE_ADMIN(), admin);
        registry.grantRole(registry.ROLE_ADMIN(), admin);
        ap.setRegistry(address(registry));
        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));

        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vm.startPrank(admin);
        ig = new MockedIG(address(vault), address(ap));
        ig.grantRole(ig.ROLE_ADMIN(), admin);
        ig.grantRole(ig.ROLE_EPOCH_ROLLER(), admin);
        vault.grantRole(vault.ROLE_ADMIN(), admin);
        vm.stopPrank();

        VaultUtils.addVaultDeposit(alice, 15000000e18, admin, address(vault), vm);
        po = TestnetPriceOracle(ap.priceOracle());
        MarketOracle ocl = MarketOracle(ap.marketOracle());


        vm.startPrank(admin);
        ig.setTradeVolatilityUtilizationRateFactor(2e18);
        ig.setTradeVolatilityTimeDecay(0.25e18);
        ig.setSigmaMultiplier(3e18);
        ocl.setImpliedVolatility(address(baseToken), address(sideToken), EpochFrequency.DAILY, 50e17);
        ocl.setDelay(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, 0, true);

        po.setTokenPrice(address(sideToken), 2000e18);
        vm.stopPrank();

        Utils.skipDay(true, vm);

        vm.prank(admin);
        registry.registerDVP(address(ig));
        vm.prank(admin);
        MockedVault(vault).setAllowedDVP(address(ig));
        feeManager = FeeManager(ap.feeManager());
        
        vm.prank(admin);
        ig.rollEpoch();
    }
    /**
        @dev Scenario 1.1 - Buy Bull at Start.
        Strike = 2000
        t_exp = 1 minute
        Buy 1 bull at: price = 2000 - 20 * x
        Issue:
            - Arithmetic underflow or overflow at 1820
     */
    function testBuyPremiumScenario1() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo > 0) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            (premium, ) = _assurePremium(charlie, 2000e18, 1e18, 0);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 1e18, 0, premium, 0.1e18,0);
            prezzo -= 20e18;
        }
    }

    /**
        @dev Scenario 1.2 - Buy Bull at Expiration.
        Strike = 2000
        Issue:
            - Arithmetic underflow or overflow at 300
     */
    function testBuySellPremiumScenario12() public {
        vm.warp(block.timestamp + 86340);

        vm.prank(admin);
        po.setTokenPrice(address(sideToken), 50e18);

        (uint256 premiumUp, uint256 premiumDown) = ig.premium(2000, 15e18, 0);
        (premiumUp, premiumDown) = ig.premium(2000, 0, 15e18);

        (uint256 premium_, ) = _assurePremium(charlie, 2000e18, 0, 15e18);

        vm.prank(charlie);
        ig.mint(charlie, 2000e18, 0, 15e18, premium_, 0.1e18,0);

        (premium_, ) = _assurePremium(charlie, 2000e18, 15e18, 0);

        vm.prank(charlie);
        ig.mint(charlie, 2000e18, 15e18, 0, premium_, 0.1e18,0);
    }

    /**
        @dev Scenario 2.1 - Buy Bear at Start.
        Strike = 2000
        t_exp = 1 day
        Buy 1 bear at: price = 2000 + 20 * x
        Issue:
            - Arithmetic underflow or overflow at 12600
    */  
    function testBuyPremiumScenario21() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo < 100000e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            (premium, ) = _assurePremium(charlie, 2000e18, 0, 1e18);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 0, 1e18, premium, 0.1e18,0);
            prezzo += 20e18;
        }
    }

    /**
        @dev Scenario 3.1 - Sell Bull at Expiration.
        Strike = 2000
        t_exp = 1 day
        Buy 1 bull at: price = 2000
        t_exp = 1 minute
        Sell 1 bull at: price = 2000 - 20 * x
        Issue:
            - Insufficient allowance at 1900
     */
    function testBuySellPremium0Scenario3() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo > 300e18) {

            (premium, ) = _assurePremium(charlie, 2000e18, 1e18, 0);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 1e18, 0, premium, 0.1e18,0);
            prezzo -= 20e18;
        }

        prezzo = 2000e18;
        uint256 epoch = ig.currentEpoch();

        vm.warp(block.timestamp + 86340);
        while (prezzo > 300e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            vm.startPrank(charlie);
            (premium, ) = ig.payoff(epoch, 2000e18, 1e18, 0);
            ig.burn(epoch, charlie, 2000e18, 1e18, 0, premium, 0.1e18);
            vm.stopPrank();
            prezzo -= 20e18;
        }
    }

    /**
        @dev Scenario 3.2 - Sell Bull at Start.
        Strike = 2000
        t_exp = 23 hours
        Buy 1 bull at: price = 2000
        t_exp = 23 hours
        Sell 1 bull at: price = 2000 - 20 * x
        Issue:
            - Arithmetic overflow/underflow at 320
     */
    function testBuySellPremium0Scenario31() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo > 300e18) {

            (premium, ) = _assurePremium(charlie, 2000e18, 1e18, 0);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 1e18, 0, premium, 0.1e18,0);
            prezzo -= 20e18;
        }

        prezzo = 2000e18;
        uint256 epoch = ig.currentEpoch();

        vm.warp(block.timestamp + 3600);
        while (prezzo > 300e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            vm.startPrank(charlie);
            (premium, ) = ig.payoff(epoch, 2000e18, 1e18, 0);
            ig.burn(epoch, charlie, 2000e18, 1e18, 0, premium, 0.1e18);
            vm.stopPrank();
            prezzo -= 20e18;
        }
    }

    /**
        @dev Scenario 4.1 - Sell Bear at Expiration.
        Strike = 2000
        t_exp = 1 day
        Buy 1 bear at: price = 2000
        t_exp = 1 minute
        Sell 1 bear at: price = 2000 + 20 * x
        Issue:
            - No issue (tested up to 50k)
     */
    function testBuySellPremium0Scenario41() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo < 50000e18) {

            (premium, ) = _assurePremium(charlie, 2000e18, 0, 1e18);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 0, 1e18, premium, 0.1e18,0);
            prezzo += 20e18;
        }

        prezzo = 2000e18;
        uint256 epoch = ig.currentEpoch();

        vm.warp(block.timestamp + 86340);
        while (prezzo < 50000e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            vm.startPrank(charlie);
            (uint256 payoff, ) = ig.payoff(epoch, 2000e18, 0, 1e18);
            ig.burn(epoch, charlie, 2000e18, 0, 1e18, payoff, 0.1e18);
            vm.stopPrank();
            prezzo += 20e18;
        }
    }

    /**
        @dev Scenario 4.2 - Sell Bear at Start.
        Strike = 2000
        t_exp = 1 day
        Buy 1 bear at: price = 2000
        t_exp = 23 hours
        Sell 1 bear at: price = 2000 + 20 * x
        Issue:
            - Arithmetic overflow/underflow at 11940
     */
    function testBuySellPremium0Scenario42() public {
        uint256 premium;

        uint256 prezzo = 2000e18;
        while (prezzo < 50000e18) {

            (premium, ) = _assurePremium(charlie, 2000e18, 0, 1e18);
            vm.prank(charlie);
            ig.mint(charlie, 2000e18, 0, 1e18, premium, 0.1e18,0);
            prezzo += 20e18;
        }

        prezzo = 2000e18;
        uint256 epoch = ig.currentEpoch();

        vm.warp(block.timestamp + 3600);
        while (prezzo < 50000e18) {
            vm.startPrank(admin);
            po.setTokenPrice(address(sideToken), prezzo);
            vm.stopPrank();

            vm.startPrank(charlie);
            (uint256 payoff, ) = ig.payoff(epoch, 2000e18, 0, 1e18);
            ig.burn(epoch, charlie, 2000e18, 0, 1e18, payoff, 0.1e18);
            vm.stopPrank();
            prezzo += 20e18;
        }
    }

    function _assurePremium(
        address user,
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) private returns (uint256 premium_, uint256 fee) {
        (premium_, fee) = ig.premium(strike, amountUp, amountDown);
        TokenUtils.provideApprovedTokens(admin, address(baseToken), user, address(ig), premium_, vm);
    }
}
