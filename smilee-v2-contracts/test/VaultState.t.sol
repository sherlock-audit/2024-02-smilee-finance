// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {IExchange} from "@project/interfaces/IExchange.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {Vault} from "@project/Vault.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {Utils} from "./utils/Utils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedVault} from "./mock/MockedVault.sol";

contract VaultStateTest is Test {
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 constant ExceedsMaxDeposit = bytes4(keccak256("ExceedsMaxDeposit()"));
    
    bytes constant VaultPaused = bytes("Pausable: paused");

    address admin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    MockedVault vault;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.startPrank(admin);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), admin);
        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vm.startPrank(admin);
        vault.grantRole(vault.ROLE_ADMIN(), admin);
        vault.grantRole(vault.ROLE_EPOCH_ROLLER(), admin);
        vm.stopPrank();
    }

    function testEpochRollableOnlyByAdminWhenNotLinkedToDVP() public {
        assertEq(address(0), vault.dvp());

        Epoch memory epoch = vault.getEpoch();
        assertNotEq(epoch.previous, epoch.current);
        uint256 epochBeforeRoll = epoch.current;

        Utils.skipDay(true, vm);

        vm.prank(alice);
        vm.expectRevert();
        vault.rollEpoch();

        vm.prank(admin);
        vault.rollEpoch();

        epoch = vault.getEpoch();
        assertEq(epochBeforeRoll, epoch.previous);
        assertNotEq(epoch.previous, epoch.current);
    }

    function testEpochRollableOnlyByDVPWhenLinked() public {
        assertEq(address(0), vault.dvp());

        Epoch memory epoch = vault.getEpoch();
        assertNotEq(epoch.previous, epoch.current);
        uint256 epochBeforeRoll = epoch.current;

        Utils.skipDay(true, vm);

        address dvp = address(0x04);

        vm.prank(admin);
        MockedVault(vault).setAllowedDVP(dvp);

        vm.prank(alice);
        vm.expectRevert();
        vault.rollEpoch();

        vm.startPrank(admin);
        vault.renounceRole(vault.ROLE_EPOCH_ROLLER(), admin);
        vm.expectRevert();
        vault.rollEpoch();
        vm.stopPrank();

        vm.prank(dvp);
        vault.rollEpoch();

        epoch = vault.getEpoch();
        assertEq(epochBeforeRoll, epoch.previous);
        assertNotEq(epoch.previous, epoch.current);
    }

    function testCheckPendingDepositAmount() public {
        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100, alice, 0);

        uint256 stateDepositAmount = VaultUtils.vaultState(vault).liquidity.pendingDeposits;
        assertEq(100, stateDepositAmount);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100, alice, 0);
        stateDepositAmount = VaultUtils.vaultState(vault).liquidity.pendingDeposits;
        assertEq(200, stateDepositAmount);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        stateDepositAmount = VaultUtils.vaultState(vault).liquidity.pendingDeposits;
        assertEq(0, stateDepositAmount);
    }

    function testHeldShares() public {
        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);
        vm.prank(alice);
        vault.deposit(100, alice, 0);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50);

        uint256 newHeldShares = VaultUtils.vaultState(vault).withdrawals.newHeldShares;
        assertEq(50, newHeldShares);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 heldShares = VaultUtils.vaultState(vault).withdrawals.heldShares;
        newHeldShares = VaultUtils.vaultState(vault).withdrawals.newHeldShares;
        assertEq(50, heldShares);
        assertEq(0, newHeldShares);

        vm.prank(alice);
        vault.completeWithdraw();

        heldShares = VaultUtils.vaultState(vault).withdrawals.heldShares;
        assertEq(0, heldShares);
    }

    // ToDo: Add comments
    function testEqualWeightRebalance(uint256 sideTokenPrice) public {
        uint256 amountToDeposit = 100 ether;
        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), amountToDeposit, vm);
        vm.prank(alice);
        vault.deposit(amountToDeposit, alice, 0);

        vm.assume(sideTokenPrice > 0 && sideTokenPrice < type(uint64).max);
        TestnetPriceOracle priceOracle = TestnetPriceOracle(AddressProvider(vault.addressProvider()).priceOracle());
        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        uint256 expectedBaseTokens = amountToDeposit / 2;
        uint256 expectedSideTokens = (expectedBaseTokens * 1e18) / sideTokenPrice;
        (uint256 baseTokens, uint256 sideTokens) = vault.balances();

        assertApproxEqAbs(expectedBaseTokens, baseTokens, 1e3);
        assertApproxEqAbs(expectedSideTokens, sideTokens, 1e3);
    }

    /**
        Check state of the vault after `deltaHedge()` call
     */
      function testDeltaHedge(uint128 amountToDeposit, int128 amountToHedge, uint32 sideTokenPrice) public {
        // TODO: review as it reverts with InsufficientInput() when [1.455e22, 1.694e30, 4.294e9]
        // An amount should be always deposited
        // TBD: what if depositAmount < 1 ether ?


        vm.prank(admin);
        vault.setMaxDeposit(type(uint256).max);

        vm.assume(amountToDeposit > 1 ether);
        vm.assume(sideTokenPrice > 0);

        uint256 amountToHedgeAbs = amountToHedge > 0
            ? uint256(uint128(amountToHedge))
            : uint256(-int256(amountToHedge));

        AddressProvider ap = AddressProvider(vault.addressProvider());
        TestnetPriceOracle priceOracle = TestnetPriceOracle(ap.priceOracle());

        vm.prank(admin);
        priceOracle.setTokenPrice(address(sideToken), sideTokenPrice);

        IExchange exchange = IExchange(ap.exchangeAdapter());
        uint256 baseTokenSwapAmount = exchange.getOutputAmount(
            address(sideToken),
            address(baseToken),
            amountToHedgeAbs
        );

        int256 expectedSideTokenDelta = int256(amountToHedge);
        int256 expectedBaseTokenDelta = amountToHedge > 0 ? -int256(baseTokenSwapAmount) : int256(baseTokenSwapAmount);

        TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), amountToDeposit, vm);
        vm.prank(alice);
        vault.deposit(amountToDeposit, alice, 0);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        (uint256 btAmount, uint256 stAmount) = vault.balances();

        if (
            (amountToHedge > 0 && (baseTokenSwapAmount * 975 / 1000) + 1 > btAmount) || (amountToHedge < 0 && amountToHedgeAbs > stAmount)
        ) {
            // InsufficientLiquidity or UniswapV3: "Too much requested"
            vm.expectRevert();
            vault.deltaHedgeMock(amountToHedge);
            return;
        }


        if(baseTokenSwapAmount > btAmount) {
            uint256 sideTokenDelta = exchange.getInputAmount( 
            address(sideToken),
            address(baseToken),
            baseTokenSwapAmount - baseTokenSwapAmount * 975 / 1000);
            expectedSideTokenDelta = int256(amountToHedge) - int256(sideTokenDelta);
            
            baseTokenSwapAmount = baseTokenSwapAmount * 975 / 1000;
            expectedBaseTokenDelta = amountToHedge > 0 ? -int256(baseTokenSwapAmount) : int256(baseTokenSwapAmount);
        }

        vault.deltaHedgeMock(amountToHedge);
        (uint256 btAmountAfter, uint256 stAmountAfter) = vault.balances();

        assertApproxEqAbs(int256(btAmount) + expectedBaseTokenDelta, int256(btAmountAfter), _tolerance(btAmountAfter));
        assertApproxEqAbs(int256(stAmount) + expectedSideTokenDelta, int256(stAmountAfter), _tolerance(stAmountAfter));
    }

    function _tolerance(uint256 value) private pure returns (uint256) {
        if (value < 100) {
            return 1;
        }
        return (value * 0.015e18) / 1e18;
    }

    /**
        Check how initialLiquidity change after roll epoch due to operation done.
     */
    function testInitialLiquidity() public {
        uint256 initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(0, initialLiquidity);

        VaultUtils.addVaultDeposit(alice, 1 ether, admin, address(vault), vm);
        // initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        // assertEq(0, initialLiquidity);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(1 ether, initialLiquidity);

        VaultUtils.addVaultDeposit(address(0x3), 0.5 ether, admin, address(vault), vm);

        vm.prank(alice);
        // Alice want to withdraw half of her shares.
        vault.initiateWithdraw(0.5 ether);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();
        // Alice 0.5 ether + bob 0.5 ether
        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(1 ether, initialLiquidity);

        vm.prank(alice);
        vault.completeWithdraw();

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();
        // Complete withdraw without any operation cannot update the initialLiquidity state
        initialLiquidity = VaultUtils.vaultState(vault).liquidity.lockedInitially;
        assertEq(1 ether, initialLiquidity);
    }

    function testMaxDeposit() public {
        vm.prank(admin);
        vault.setMaxDeposit(1000e18);

        VaultUtils.addVaultDeposit(alice, 100e18, admin, address(vault), vm);
        (, , , uint256 cumulativeAmount) = vault.depositReceipts(alice);

        assertEq(VaultUtils.vaultState(vault).liquidity.totalDeposit, 100e18);
        assertEq(cumulativeAmount, 100e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        // simple withdraw

        vm.prank(alice);
        vault.initiateWithdraw(10e18);

        (, , , cumulativeAmount) = vault.depositReceipts(alice);
        assertEq(VaultUtils.vaultState(vault).liquidity.totalDeposit, 90e18);
        assertEq(cumulativeAmount, 90e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        // simple deposit

        VaultUtils.addVaultDeposit(alice, 20e18, admin, address(vault), vm);

        vm.prank(alice);
        vault.completeWithdraw();

        (, , , cumulativeAmount) = vault.depositReceipts(alice);
        assertEq(VaultUtils.vaultState(vault).liquidity.totalDeposit, 110e18);
        assertEq(cumulativeAmount, 110e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        // withdraw and deposit

        vm.prank(alice);
        vault.initiateWithdraw(50e18);
        VaultUtils.addVaultDeposit(alice, 30e18, admin, address(vault), vm);

        (, , , cumulativeAmount) = vault.depositReceipts(alice);
        assertEq(VaultUtils.vaultState(vault).liquidity.totalDeposit, 90e18);
        assertEq(cumulativeAmount, 90e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        // multiple withdraw

        vm.prank(alice);
        vault.initiateWithdraw(30e18);

        vm.prank(alice);
        vault.initiateWithdraw(30e18);

        (, , , cumulativeAmount) = vault.depositReceipts(alice);
        assertEq(VaultUtils.vaultState(vault).liquidity.totalDeposit, 30e18);
        assertEq(cumulativeAmount, 30e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        // multiple users

        VaultUtils.addVaultDeposit(bob, 20e18, admin, address(vault), vm);
        VaultUtils.addVaultDeposit(alice, 10e18, admin, address(vault), vm);

        (, , , cumulativeAmount) = vault.depositReceipts(bob);
        assertEq(VaultUtils.vaultState(vault).liquidity.totalDeposit, 60e18);
        assertEq(cumulativeAmount, 20e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        // threshold check

        TokenUtils.provideApprovedTokens(admin, vault.baseToken(), alice, address(vault), 1000 ether, vm);
        vm.expectRevert(ExceedsMaxDeposit);
        vault.deposit(941e18, alice, 0);
    }

    /**
     * Check all the User Vault's features are disabled when Vault is paused.
     */
    function testVaultPaused() public {
        VaultUtils.addVaultDeposit(alice, 1 ether, admin, address(vault), vm);
        TokenUtils.provideApprovedTokens(admin, vault.baseToken(), alice, address(vault), 1 ether, vm);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        assertEq(vault.paused(), false);

        vm.expectRevert();
        vault.changePauseState();

        vm.prank(admin);
        vault.changePauseState();
        assertEq(vault.paused(), true);

        vm.startPrank(alice);
        vm.expectRevert(VaultPaused);
        vault.deposit(1e16, alice, 0);

        vm.expectRevert(VaultPaused);
        vault.initiateWithdraw(1e17);

        vm.expectRevert(VaultPaused);

        vault.completeWithdraw();

        vm.stopPrank();

        Utils.skipDay(true, vm);

        vm.prank(admin);
        vault.rollEpoch();

        // From here on, all the vault functions should working properly
        vm.prank(admin);
        vault.changePauseState();
        assertEq(vault.paused(), false);

        vm.startPrank(alice);
        vault.deposit(1e17, alice, 0);

        vault.initiateWithdraw(1e17);
        vm.stopPrank();

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();
    }

    /**
     * 
     */
    function testVaultRevertInsufficientLiquidityNewPendingPayoff() public {
        VaultUtils.addVaultDeposit(alice, 100e18, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        vault.setAllowedDVP(admin);
        
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("reservePayoff()"))));
        vault.reservePayoff(101e18);
    }

        /**
     * 
     */
    function testVaultRevertInsufficientLiquidityNewPendingPayoffWithMoveValue() public {
        VaultUtils.addVaultDeposit(alice, 100e18, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        vault.setAllowedDVP(admin);
        
        vm.prank(admin);
        vault.reservePayoff(99e18);

        vault.moveValue(-1000); 

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_beforeRollEpoch()::lockedLiquidity <= _state.liquidity.newPendingPayoffs"))));
        vault.rollEpoch();
    }

    function testVaultRevertInsufficientLiquiditySharePriceZeroMoveValue() public {
        VaultUtils.addVaultDeposit(alice, 100e18, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        vault.setAllowedDVP(admin);
        
        vm.prank(admin);
        vault.reservePayoff(99e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vault.moveValue(-10000); 

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector,  bytes4(keccak256("_beforeRollEpoch()::sharePrice == 0"))));
        vault.rollEpoch();
    }

    function testVaultRevertInsufficientLiquiditySharePriceZeroReserveAllLiquidityToPayoff() public {
        VaultUtils.addVaultDeposit(alice, 100e18, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        vault.setAllowedDVP(admin);
        
        vm.prank(admin);
        vault.reservePayoff(100e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_beforeRollEpoch()::sharePrice == 0"))));
        vault.rollEpoch();
    }

    function testVaultRevertInsufficientLiquiditySharePriceZeroMoveValueScenario() public {
        VaultUtils.addVaultDeposit(alice, 100e18, admin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vm.prank(admin);
        vault.setAllowedDVP(admin);
        
        vm.prank(admin);
        vault.reservePayoff(99e18);


        Utils.skipDay(true, vm);
        vm.prank(admin);
        vault.rollEpoch();

        vault.moveBaseToken(-1e18);

        Utils.skipDay(true, vm);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_notionalBaseTokens()"))));
        vault.rollEpoch();
    }

    // ToDo: Fare con Mattia
    // function testVaultRevertInsufficientLiquidityFuzzy(uint128 aliceDeposit, uint128 bobDeposit, uint128 firstReservePayoff, uint128 firstMoveToken) public {
    //     vm.assume(aliceDeposit > 0);
    //     vm.assume(bobDeposit > 0);
    //     vm.assume(bobDeposit + aliceDeposit <= type(uint128).max);
    //     vm.assume(firstMoveToken <= (aliceDeposit + bobDeposit) / 2);
        
        
    //     vm.prank(admin);
    //     vault.setMaxDeposit(type(uint256).max);
        
    //     VaultUtils.addVaultDeposit(alice, aliceDeposit, admin, address(vault), vm);
    //     VaultUtils.addVaultDeposit(bob, bobDeposit, admin, address(vault), vm);

    //     Utils.skipDay(true, vm);
    //     vm.prank(admin);
    //     vault.rollEpoch();

    //     vm.prank(bob);
    //     vault.initiateWithdraw(bobDeposit);

    //     vm.prank(admin);
    //     vault.setAllowedDVP(admin);
        
    //     if (firstReservePayoff > aliceDeposit + bobDeposit) {
    //         vm.prank(admin);
    //         vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("reservePayoff()"))));
    //         vault.reservePayoff(firstReservePayoff);
    //     }

    //     vm.prank(admin);
    //     vault.reservePayoff(firstReservePayoff);

    //     vault.moveBaseToken(int256(-int128(firstMoveToken)));
        
    //     Utils.skipDay(true, vm);
    //     if(firstReservePayoff + firstMoveToken > aliceDeposit + bobDeposit) {
    //         vm.prank(admin);
    //         vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_beforeRollEpoch():lockedLiquidity <= _state.liquidity.newPendingPayoffs"))));
    //         vault.rollEpoch();
    //     }

    //     if(firstReservePayoff + firstMoveToken == aliceDeposit + bobDeposit) {
    //         vm.prank(admin);
    //         vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientLiquidity.selector, bytes4(keccak256("_beforeRollEpoch():sharePrice == 0"))));
    //         vault.rollEpoch();
    //     }

    //     vm.prank(admin);
    //     vault.rollEpoch();
    // }


    // /**
    //     Test that vault accounting properties are correct after calling `moveAsset()`
    //  */
    // function testMoveAssetPull() public {
    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);

    //     vm.prank(alice);
    //     vault.deposit(100, 0);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     // assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(true, vm);
    //     vault.rollEpoch();

    //     assertEq(50, baseToken.balanceOf(address(vault)));
    //     // assertEq(50, VaultUtils.vaultState(vault).liquidity.locked);

    //     vault.moveAsset(-30);

    //     Utils.skipDay(false, vm);
    //     vault.rollEpoch();

    //     assertEq(35, baseToken.balanceOf(address(vault)));
    //     // assertEq(35, VaultUtils.vaultState(vault).liquidity.locked);
    // }

    // function testMoveAssetPullFail() public {
    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);

    //     vm.prank(alice);
    //     vault.deposit(100, 0);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     // assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(true, vm);
    //     vault.rollEpoch();

    //     assertEq(50, baseToken.balanceOf(address(vault)));
    //     // assertEq(50, VaultUtils.vaultState(vault).liquidity.locked);

    //     vm.expectRevert(ExceedsAvailable);
    //     vault.moveAsset(-101);
    // }

    // function testMoveAssetPush() public {
    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);

    //     vm.prank(alice);
    //     vault.deposit(100, 0);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     // assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(true, vm);
    //     vault.rollEpoch();

    //     assertEq(50, baseToken.balanceOf(address(vault)));
    //     // assertEq(50, VaultUtils.vaultState(vault).liquidity.locked);

    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), admin, address(vault), 100, vm);
    //     vm.prank(admin);
    //     vault.moveAsset(100);

    //     Utils.skipDay(false, vm);
    //     vault.rollEpoch();

    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     // assertEq(100, VaultUtils.vaultState(vault).liquidity.locked);
    // }

    // /**
    //     Test that vault accounting properties are correct after calling `moveAsset()`
    //  */
    // function testMoveAsset() public {
    //     Vault vault = _createMarket();
    //     vault.rollEpoch();

    //     TokenUtils.provideApprovedTokens(admin, address(baseToken), alice, address(vault), 100, vm);

    //     vm.prank(alice);
    //     vault.deposit(100, 0);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     assertEq(0, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(true, vm);
    //     vault.rollEpoch();

    //     vm.prank(alice);
    //     vault.initiateWithdraw(40);
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     assertEq(100, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(false, vm);
    //     vault.rollEpoch();
    //     assertEq(100, baseToken.balanceOf(address(vault)));
    //     assertEq(60, VaultUtils.vaultState(vault).liquidity.locked);

    //     vault.moveAsset(-30);
    //     assertEq(70, baseToken.balanceOf(address(vault)));
    //     assertEq(30, VaultUtils.vaultState(vault).liquidity.locked);

    //     Utils.skipDay(false, vm);
    //     vault.rollEpoch();

    //     vm.prank(alice);
    //     vault.completeWithdraw();
    //     (, uint256 withdrawalShares) = vault.withdrawals(alice);

    //     // assertEq(60, vault.totalSupply());
    //     // assertEq(60, baseToken.balanceOf(address(vault)));
    //     // assertEq(40, baseToken.balanceOf(address(alice)));
    //     // assertEq(0, withdrawalShares);
    // }
}
