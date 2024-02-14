// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {Vault} from "@project/Vault.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "@project/AddressProvider.sol";

/**
    @title Test case for underlying asset going to zero
    @dev This should never happen, still we need to test shares value goes to zero, users deposits can be rescued and
         new deposits are not allowed
 */
contract VaultDeathTest is Test {
    bytes4 constant NothingToRescue = bytes4(keccak256("NothingToRescue()"));
    bytes4 constant VaultDead = bytes4(keccak256("VaultDead()"));
    bytes4 constant EpochFinished = bytes4(keccak256("EpochFinished()"));
    bytes4 constant VaultNotDead = bytes4(keccak256("VaultNotDead()"));
    bytes4 constant DeadManualKillReason = bytes4(keccak256("ManualKill"));

    address tokenAdmin = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    TestnetToken baseToken;
    TestnetToken sideToken;
    MockedVault vault;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.prank(tokenAdmin);
        AddressProvider ap = new AddressProvider(0);

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, tokenAdmin, vm));
        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vm.startPrank(tokenAdmin);
        vault.grantRole(vault.ROLE_ADMIN(), tokenAdmin);
        vault.grantRole(vault.ROLE_EPOCH_ROLLER(), tokenAdmin);
        vm.stopPrank();
    }


    function testVaultManualDead() public {
        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        (, , , , , , , , bool killed) = vault.vaultState();
        assertEq(true, killed);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        assertEq(true, VaultUtils.vaultState(vault).dead);
    }

    function testVaultManualDeadRescueShares() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.rescueShares();

        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(0, vault.totalSupply());
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(100e18, baseToken.balanceOf(alice));
    }

    function testVaultManualDeadMultipleRescueShares() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 200e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.rescueShares();

        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(200e18, vault.totalSupply());
        (, , , uint256 cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(200e18, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(0, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(100e18, baseToken.balanceOf(alice));

        vm.prank(bob);
        vault.rescueShares();

        (uint256 heldByAccountBob, uint256 heldByVaultBob) = vault.shareBalances(bob);
        assertEq(0, vault.totalSupply());
        (, , , uint256 cumulativeAmountBob) = vault.depositReceipts(bob);
        assertEq(0, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(0, cumulativeAmountBob);
        assertEq(0, heldByVaultBob);
        assertEq(0, heldByAccountBob);
        assertEq(200e18, baseToken.balanceOf(bob));
    }

    // ToDo: review as now the completeWithdraw can be done even if the epoch finished
    function testVaultManualDeadInitiateBeforeEpochOfDeathEpochFinished() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50e18);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        // Skip another day to simulate the epochFrozen scenarios.
        // In this case, the "traditional" completeWithdraw shouldn't work due to epochFrozen error.
        Utils.skipDay(true, vm);

        vm.prank(alice);
        vault.rescueShares();

        // Check if alice has rescued all her shares
        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(0, vault.totalSupply());
        (, , , uint256 cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(0, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(0, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(100e18, baseToken.balanceOf(alice));
    }

    function testVaultManualDeadInitiateBeforeEpochOfDeath() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.initiateWithdraw(50e18);

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.completeWithdraw();

        // Check if alice has rescued all her shares
        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(50e18, vault.totalSupply());
        (, , , uint256 cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(50e18, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(50e18, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(50e18, heldByAccountAlice);
        assertEq(50e18, baseToken.balanceOf(alice));

        vm.prank(alice);
        vault.rescueShares();

        // Check if alice has rescued all her shares
        (heldByAccountAlice, heldByVaultAlice) = vault.shareBalances(alice);
        assertEq(0, vault.totalSupply());
        (, , , cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(0, VaultUtils.vaultState(vault).liquidity.totalDeposit);
        assertEq(0, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(100e18, baseToken.balanceOf(alice));
    }

    function testVaultManualDeadDepositBeforeEpochOfDeath() public {
        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100e18, tokenAdmin, address(vault), vm);

        vm.prank(tokenAdmin);
        vault.killVault();

        Utils.skipDay(true, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.rescueShares();

        assertEq(0, vault.totalSupply());
        assertEq(0, VaultUtils.vaultState(vault).liquidity.totalDeposit);

        // Check if alice has rescued all her shares
        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = vault.shareBalances(alice);
        (, , , uint256 cumulativeAmountAlice) = vault.depositReceipts(alice);
        assertEq(0, cumulativeAmountAlice);
        assertEq(0, heldByVaultAlice);
        assertEq(0, heldByAccountAlice);
        assertEq(200e18, baseToken.balanceOf(alice));
    }
}
