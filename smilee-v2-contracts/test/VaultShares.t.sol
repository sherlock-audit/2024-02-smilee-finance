// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {Vault} from "@project/Vault.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "@project/AddressProvider.sol";

contract VaultSharesTest is Test {
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 constant ExistingIncompleteWithdraw = bytes4(keccak256("ExistingIncompleteWithdraw()"));
    bytes4 constant VaultDead = bytes4(keccak256("VaultDead()"));
    bytes4 constant VaultNotDead = bytes4(keccak256("VaultNotDead()"));
    bytes4 constant EpochFinished = bytes4(keccak256("EpochFinished()"));
    bytes4 constant WithdrawNotInitiated = bytes4(keccak256("WithdrawNotInitiated()"));
    bytes4 constant WithdrawTooEarly = bytes4(keccak256("WithdrawTooEarly()"));

    address tokenAdmin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    MockedVault vault;

    /**
     * Setup function for each test.
     */
    function setUp() public {
        vm.warp(EpochFrequency.REF_TS + 1);

        vm.startPrank(tokenAdmin);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), tokenAdmin);
        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, tokenAdmin, vm));
        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vm.startPrank(tokenAdmin);
        vault.grantRole(vault.ROLE_ADMIN(), tokenAdmin);
        vault.grantRole(vault.ROLE_EPOCH_ROLLER(), tokenAdmin);
        vm.stopPrank();
    }

    function testDeposit() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        // initial share price is 1:1, so expect 100 shares to be minted
        assertEq(100, vault.totalSupply());
        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(alice);
        assertEq(0, baseToken.balanceOf(alice));
        assertEq(0, shares);
        assertEq(100, unredeemedShares);
        // check lockedLiquidity
        uint256 lockedLiquidity = vault.v0();
        assertEq(100, lockedLiquidity);
    }

    function testRedeemFail() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(ExceedsAvailable);
        vault.redeem(150);
    }

    function testDepositAmountZeroFail() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(AmountZero);
        vault.deposit(0, alice, 0);
    }

    function testDepositEpochFinishedFail() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        Utils.skipDay(false, vm);
        vm.expectRevert(EpochFinished);
        vault.deposit(100, alice, 0);
    }

    function testInitWithdrawEpochFinishedFail() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        Utils.skipDay(false, vm);
        vm.expectRevert(EpochFinished);
        vault.initiateWithdraw(100);
    }

    function testCompleteWithdrawEpochFinishedSuccess() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        assertEq(0, vault.totalSupply()); // shares are minted at next epoch change

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        
        vm.prank(alice);
        vault.initiateWithdraw(100);
        
        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        
        Utils.skipDay(true, vm);
        vm.prank(alice);
        vault.completeWithdraw();   

        assertEq(0, vault.totalSupply());
    }

    /**
        Wallet deposits twice (or more) in the same epoch. The amount of the shares minted for the user is the sum of all deposits.
     */
    function testDoubleDepositSameEpoch() public {
        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), alice, address(vault), 100, vm);
        vm.startPrank(alice);
        vault.deposit(50, alice, 0);
        vault.deposit(50, alice, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        (uint256 vaultBaseTokenBalance, ) = vault.balances();
        assertEq(100, vault.totalSupply());
        assertEq(50, vaultBaseTokenBalance);
        assertEq(100, heldByVaultAlice);
    }

    function testRedeemZeroFail() public {
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(AmountZero);
        vault.redeem(0);
    }

    function testRedeem() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.redeem(50);

        (uint256 shares, uint256 unredeemedShares) = vault.shareBalances(alice);
        assertEq(50, shares);
        assertEq(50, unredeemedShares);
        assertEq(50, vault.balanceOf(alice));

        // check lockedLiquidity. It still remains the same
        uint256 lockedLiquidity = vault.v0();
        assertEq(100, lockedLiquidity);
    }

    function testInitWithdrawWithoutSharesFail() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        vm.expectRevert(ExceedsAvailable);
        vault.initiateWithdraw(100);
    }

    function testInitWithdrawZeroFail() public {
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(AmountZero);
        vault.initiateWithdraw(0);
    }

    /**
        Wallet redeems its shares and start a withdraw. Everithing goes ok.
     */
    function testInitWithdrawWithRedeem() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.startPrank(alice);
        vault.redeem(100);
        vault.initiateWithdraw(100);
        vm.stopPrank();
        (, uint256 withdrawalShares) = vault.withdrawals(alice);

        assertEq(0, vault.balanceOf(alice));
        assertEq(100, withdrawalShares);
    }

    /**
        Wallet withdraws without redeeming its shares before. An automatic redeem is executed by the protocol.
     */
    function testInitWithdrawNoRedeem() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(100);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(0, vault.balanceOf(alice));
        assertEq(100, withdrawalShares);
    }

    /**
        Wallet withdraws twice (or more) in the same epoch. The amount of the shares to withdraw has to be the sum of each.
     */
    function testInitWithdrawTwiceSameEpoch() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.startPrank(alice);
        vault.initiateWithdraw(50);
        vault.initiateWithdraw(50);
        vm.stopPrank();

        (, uint256 aliceWithdrawalShares) = vault.withdrawals(alice);
        assertEq(100, aliceWithdrawalShares);
    }

    /**
        Wallet withdraws twice (or more) in subsequent epochs. A ExistingIncompleteWithdraw error is expected.
     */
    function testInitWithdrawTwiceDifferentEpochs() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(ExistingIncompleteWithdraw);
        vault.initiateWithdraw(50);
    }

    /**
        Wallet completes withdraw without init. A WithdrawNotInitiated error is expected.
     */
    function testCompleteWithdrawWithoutInitFail() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vm.expectRevert(WithdrawNotInitiated);
        vault.completeWithdraw();
    }

    /**
        Wallet inits and completes a withdrawal procedure in the same epoch. An WithdrawTooEarly error is expected.
     */
    function testInitAndCompleteWithdrawSameEpoch() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.startPrank(alice);
        vault.initiateWithdraw(100);
        vm.expectRevert(WithdrawTooEarly);
        vault.completeWithdraw();
        vm.stopPrank();
    }

    /**
        Wallet makes a partial withdraw without redeeming its shares. All shares are automatically redeemed and some of them held by the vault for withdrawal.
     */
    function testInitWithdrawPartWithoutRedeem() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50);
        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(50, vault.balanceOf(alice));
        assertEq(50, vault.balanceOf(address(vault)));
        assertEq(50, withdrawalShares);
    }

    function testWithdraw() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(40);
        // a max redeem is done within initiateWithdraw so unwithdrawn shares remain to alice
        assertEq(40, vault.balanceOf(address(vault)));
        assertEq(60, vault.balanceOf(alice));
        // check lockedLiquidity
        uint256 lockedLiquidity = vault.v0();
        assertEq(100, lockedLiquidity);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        assertEq(40, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        // check lockedLiquidity
        lockedLiquidity = vault.v0();
        assertEq(60, lockedLiquidity);

        vm.prank(alice);
        vault.completeWithdraw();
        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalShares) = vault.withdrawals(alice);
        assertEq(60, vault.totalSupply());
        assertEq(40, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalShares);
    }

    /**
        - Alice deposits 100 in epoch 1 (100 shares)
        - vault notional value doubles in epoch 1
        - Bob deposit 100 in epoch 1 for epoch 2 (50 shares)
        - vault notional value doubles in epoch 2
        - Bob and Alice start a the withdraw procedure for all their shares
        - Alice should receive 400 (100*4) and Bob 200 (100*2).
     */
    function testVaultMathDoubleLiquidity() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(vault.totalSupply(), 100);
        assertEq(heldByVaultAlice, 100);

        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), tokenAdmin, address(vault), 100, vm);
        vm.prank(tokenAdmin);
        vault.moveValue(10000); // +100% Alice
        assertEq(200, vault.notional());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(150, vault.totalSupply());
        assertEq(heldByVaultBob, 50);

        vm.prank(alice);
        vault.initiateWithdraw(100);

        vm.prank(bob);
        vault.initiateWithdraw(50);

        TokenUtils.provideApprovedTokens(tokenAdmin, address(baseToken), tokenAdmin, address(vault), 300, vm);
        vm.prank(tokenAdmin);
        vault.moveValue(10000); // +200% Alice, +100% Bob
        assertEq(600, vault.notional());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        assertEq(600, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        assertEq(0, vault.notional()); // everyone withdraws, notional is 0

        vm.prank(alice);
        vault.completeWithdraw();
        assertEq(200, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(50, vault.totalSupply());
        assertEq(400, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);

        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(200, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
    }

    /**
        - Alice deposits 100 base tokens for epoch 1 (100 shares)
        - vault notional value halves in epoch 1
        - Bob deposits 100 during epoch 1 for epoch 2 (200 shares)
        - vault notional value halves in epoch 2
        - Bob and Alice start the withdraw procedure for all their shares
        - Alice should receive 25 (100/4) and Bob 50 (100/2)
     */
    function testVaultMathHalveLiquidity() public {
        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(vault.totalSupply(), 100);
        assertEq(heldByVaultAlice, 100);

        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        vault.moveValue(-5000); // -50% Alice
        assertEq(50, vault.notional());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(vault.totalSupply(), 300);
        assertEq(heldByVaultBob, 200);

        vm.prank(alice);
        vault.initiateWithdraw(100);

        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.initiateWithdraw(200);

        vault.moveValue(-5000); // -75% Alice, -50% Bob
        assertEq(75, vault.notional());

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(75, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        assertEq(0, vault.notional()); // everyone withdraws, notional is 0

        vm.prank(alice);
        vault.completeWithdraw();
        assertEq(50, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalSharesAlice) = vault.withdrawals(alice);
        assertEq(200, vault.totalSupply());
        assertEq(25, baseToken.balanceOf(address(alice)));
        assertEq(0, withdrawalSharesAlice);

        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        (, uint256 withdrawalSharesBob) = vault.withdrawals(bob);
        assertEq(0, vault.totalSupply());
        assertEq(50, baseToken.balanceOf(address(bob)));
        assertEq(0, withdrawalSharesBob);
    }

    /**
     * This test intends to check the behaviour of the Vault when someone start a withdraw and, in the next epoch
     * someone else deposits into the Vault. The expected behaviour is basicaly the withdrawal (redeemed) shares have to reduce the
     * locked liquidity balance. Who deposits after the request of withdraw must receive a number of shares calculated by subtracting the withdrawal shares amount
     * to the totalSupply(). In this case, the price must be of 1$.
     */
    function testRollEpochMathSingleInitWithdrawWithDepositWithoutCompletingWithdraw() public {
        // Roll first epoch
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(heldByVaultAlice, 100);
        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100);
        assertEq(200, vault.totalSupply());

        // Alice starts withdraw
        vm.prank(alice);
        vault.initiateWithdraw(100);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        assertEq(100, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        // ToDo: check Alice's shares

        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(200, heldByVaultBob);
        assertEq(300, vault.totalSupply());

        // Alice not compliting withdraw in this test. Check the following test
        // vm.prank(alice);
        // vault.completeWithdraw();

        vm.prank(bob);
        vault.initiateWithdraw(200);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();
        assertEq(300, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(100, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        assertEq(0, baseToken.balanceOf(alice));
        assertEq(200, baseToken.balanceOf(bob));
        assertEq(100, vault.totalSupply());
    }

    /**
     * This test intends to check the behaviour of the Vault when someone start a withdraw and, in the next epoch
     * someone else deposits into the Vault. The expected behaviour is basicaly the withdrawal (redeemed) shares have to reduce the
     * locked liquidity balance. Who deposits after the request of withdraw must receive a number of shares calculated by subtracting the withdrawal shares amount
     * to the totalSupply(). In this case, the price must be of 1$.
     * Completing or not the withdraw cannot change the behaviour.
     */
    function testRollEpochMathSingleInitAndCompletingWithdrawWithDeposit() public {
        vm.warp(block.timestamp + 1 days + 1);
        // Roll first epoch
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(heldByVaultAlice, 100);

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100);
        assertEq(vault.totalSupply(), 200);

        // Alice starts withdraw
        vm.prank(alice);
        vault.initiateWithdraw(100);

        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        Utils.skipDay(true, vm);

        uint256 currentEpoch = vault.currentEpoch();
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(100, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);

        currentEpoch = vault.currentEpoch();

        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(100, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(200, heldByVaultBob);
        assertEq(300, vault.totalSupply());

        vm.prank(alice);
        vault.completeWithdraw();

        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.initiateWithdraw(200);

        Utils.skipDay(true, vm);

        currentEpoch = vault.currentEpoch();
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(200, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.completeWithdraw();

        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        assertEq(100, baseToken.balanceOf(alice));
        assertEq(200, baseToken.balanceOf(bob));
        assertEq(0, vault.v0());
        assertEq(0, vault.totalSupply());
    }

    /**
     * This test intends to check the behaviour of the Vault when all the holder complete the withdrawal procedure.
     * The price of a single share of the first deposit after all withdraws has to be 1$ (UNIT_PRICE).
     */
    function testRollEpochMathEveryoneWithdraw() public {
        vm.warp(block.timestamp + 1 days + 1);
        // Roll first epoch
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(heldByVaultAlice, 100);

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100);
        assertEq(vault.totalSupply(), 200);

        vm.startPrank(alice);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(200, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        vm.prank(alice);
        vault.completeWithdraw();

        assertEq(100, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.completeWithdraw();

        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100);
        assertEq(vault.totalSupply(), 100);
    }

    /**
     * This test intends to check the behaviour of the Vault when all the holder start the withdrawal procedure.
     * Meanwhile someone else deposits into the Vault. The price of a single share of the first deposit after all withdraws has to stay fixed to 1$ (UNIT_PRICE).
     */
    function testRollEpochMathEveryoneWithdrawWithDeposit() public {
        vm.warp(block.timestamp + 1 days + 1);
        // Roll first epoch
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(heldByVaultAlice, 100);

        (, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100);
        assertEq(vault.totalSupply(), 200);

        vm.startPrank(alice);
        vault.initiateWithdraw(100);
        vm.stopPrank();

        vm.startPrank(bob);
        vault.initiateWithdraw(100);

        // pendingWithdrawals state have to keep its value after roll epoch

        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        vm.stopPrank();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(200, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        assertEq(100, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        vm.prank(bob);
        vault.completeWithdraw();
        assertEq(0, VaultUtils.vaultState(vault).liquidity.pendingWithdrawals);

        assertEq(100, baseToken.balanceOf(alice));
        assertEq(100, baseToken.balanceOf(bob));
        assertEq(100, vault.v0());
        assertEq(100, vault.totalSupply());
        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(heldByVaultBob, 100);

        vm.prank(bob);
        vault.initiateWithdraw(100);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(bob);
        vault.completeWithdraw();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        (, heldByVaultBob) = vault.shareBalances(bob);
        assertEq(0, heldByVaultBob);
        assertEq(0, vault.totalSupply());
        assertEq(0, vault.v0());
        assertEq(200, baseToken.balanceOf(bob));
    }

    /**
     * Test used to retrieve shares of an account before first epoch roll
     */
    function testVaultShareBalanceZeroEpochNotStarted() public {
        (uint256 heldByVaultAlice, uint256 heldByAlice) = vault.shareBalances(alice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAlice);

        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);

        //Check Share Balance of Alice epoch not rolled yet
        (heldByVaultAlice, heldByAlice) = vault.shareBalances(alice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAlice);
    }
}
