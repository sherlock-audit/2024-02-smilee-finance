// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {MasterChefSmilee} from "@project/periphery/MasterChefSmilee.sol";
import {SimpleRewarderPerSec} from "@project/periphery/SimpleRewarderPerSec.sol";
import {MockedVault} from "../mock/MockedVault.sol";
import {MasterChefUtils} from "../utils/MasterChefUtils.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {VaultUtils} from "../utils/VaultUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Utils} from "../utils/Utils.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";

contract MasterChefSmileeTest is Test {
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 constant StakeToNonVaultContract = bytes4(keccak256("StakeToNonVaultContract()"));
    bytes4 constant RewardNotZeroOrContract = bytes4(keccak256("RewardNotZeroOrContract()"));
    bytes4 constant AlreadyRegisteredVault = bytes4(keccak256("AlreadyRegisteredVault()"));

    address public tokenAdmin = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    uint256 public smileePerSec = 1;
    TestnetToken public baseToken;
    TestnetToken public sideToken;
    MockedVault public vault;
    MasterChefSmilee public mcs;
    SimpleRewarderPerSec public rewarder;

    /**
        Setup function for each test.
        @notice Deploy a vualt and a staking contract.
                Make a deposit and redeem all shares.
     */
    function setUp() public {
        vm.warp(EpochFrequency.REF_TS + 1);

        vm.startPrank(tokenAdmin);
        AddressProvider ap = new AddressProvider(0);
        mcs = new MasterChefSmilee(smileePerSec, block.timestamp, ap);

        ap.grantRole(ap.ROLE_ADMIN(), tokenAdmin);
        vm.stopPrank();

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, tokenAdmin, vm));
        baseToken = TestnetToken(vault.baseToken());
        sideToken = TestnetToken(vault.sideToken());

        vm.startPrank(tokenAdmin);
        vault.grantRole(vault.ROLE_ADMIN(), tokenAdmin);
        vault.grantRole(vault.ROLE_EPOCH_ROLLER(), tokenAdmin);
        vm.stopPrank();

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        VaultUtils.addVaultDeposit(alice, 100, tokenAdmin, address(vault), vm);
        VaultUtils.addVaultDeposit(bob, 100, tokenAdmin, address(vault), vm);

        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vault.rollEpoch();

        vm.prank(alice);
        vault.redeem(100);

        vm.prank(bob);
        vault.redeem(100);

        Utils.skipDay(false, vm);
    }

    function testAddStakingVaultFail() public {
        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        vm.expectRevert(StakeToNonVaultContract);
        mcs.add(address(0), 1, rewarder);
    }

    function testAddStakingVault() public {
        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        mcs.add(address(vault), 1, rewarder);

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));

        assertEq(1, vaultInfo.allocPoint);
        assertEq(0, vaultInfo.accSmileePerShare);
        assertEq(1, convert(ud(mcs.totalAllocPoint())));
    }

    /**
        Add the same vault twice
     */
    function testAddMultipleShareFail() public {
        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        mcs.add(address(vault), 1, rewarder);

        vm.prank(tokenAdmin);
        vm.expectRevert(AlreadyRegisteredVault);
        mcs.add(address(vault), 1, rewarder);
    }

    function testFirstDepositShareInVault() public {
        Utils.skipDay(false, vm);
        vm.prank(tokenAdmin);
        mcs.add(address(vault), 1, rewarder);

        Utils.skipDay(false, vm);

        vm.startPrank(alice);
        (uint256 shares, ) = vault.shareBalances(alice);
        assertEq(100, IERC20(vault).balanceOf(alice));
        vault.approve(address(mcs), shares);
        mcs.deposit(address(vault), shares);
        vm.stopPrank();

        // On first deposit no reward are gived

        (uint256 sharesAfterStake, ) = vault.shareBalances(alice);
        assertEq(0, sharesAfterStake);

        assertEq(100, mcs.totalStaked());

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        assertEq(block.timestamp, vaultInfo.lastRewardTimestamp);
    }

    function testMultipleDeposit() public {
        vm.prank(tokenAdmin);
        mcs.add(address(vault), 1, rewarder);
        Utils.skipDay(false, vm);

        // First deposit by Alice
        (uint256 aliceShares, ) = vault.shareBalances(alice);
        MasterChefUtils.addStakeDeposit(alice, aliceShares, address(vault), mcs, vm);

        // Collect data for test purpose
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs)); // 100
        Utils.skipDay(false, vm);
        MasterChefSmilee.VaultInfo memory vaultInfoPreDeposit = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfoPreDeposit.lastRewardTimestamp)).unwrap();

        // Second deposit on same vault (shareSupply > 0)
        (uint256 bobShares, ) = vault.shareBalances(bob);
        MasterChefUtils.addStakeDeposit(bob, bobShares, address(vault), mcs, vm);

        assertEq(200, mcs.totalStaked()); // Total stake within all vaults

        MasterChefSmilee.VaultInfo memory vaultInfoAfterDeposit = mcs.getVaultInfo(address(vault));
        assertEq(block.timestamp, vaultInfoAfterDeposit.lastRewardTimestamp);

        /**
            smileePerSec = 1
            allocPoint = 1
            totalAllocPoint = 1
            expectedRewardSupply = multiplier * smileePerSec * allocPoint / totalAllocPoint
         */
        uint256 expectedRewardSupply = ud(multiplier).unwrap();
        assertEq(expectedRewardSupply, ud(mcs.rewardSupply()).unwrap());

        // accSmileePerShare = 0
        uint256 expectedAccSmileePerSec = ud(expectedRewardSupply).div(convert(shareSupply)).unwrap();
        assertEq(expectedAccSmileePerSec, vaultInfoAfterDeposit.accSmileePerShare);
    }

    function testPendingRewardAfterTimes() public {
        vm.prank(tokenAdmin);
        mcs.add(address(vault), 1, rewarder);
        Utils.skipDay(false, vm);

        (uint256 aliceShares, ) = vault.shareBalances(alice);
        MasterChefUtils.addStakeDeposit(alice, aliceShares, address(vault), mcs, vm);

        // Collect data for test purpose
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs)); // 100

        Utils.skipDay(false, vm);

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfo.lastRewardTimestamp)).unwrap();

        (uint256 amount, uint256 rewardDebt, ) = mcs.userStakeInfo(address(vault), alice);

        /**
            smileeReward = (multiplier * smileePerSec * allocPoint / totalAllocPoint)
            pendingReward = amount * ((multiplier * smileePerSec * allocPoint / totalAllocPoint) / totalSupply)
            smileePerSec = 1
            allocPoint = 1
            totalAllocPoint = 1
            rewardDebt = 0
            pendingReward = amount * multiplier / totalAllocPoint
            amount = shareSupply -> only only deposit
            pendingReward = multiplier
        */
        uint256 expectedPendingReward = ud(amount)
            .mul(ud(multiplier))
            .div(convert(shareSupply))
            .sub(ud(rewardDebt))
            .unwrap();
        (uint256 pendingRewardToken, , ) = mcs.pendingTokens(address(vault), alice);
        assertEq(expectedPendingReward, pendingRewardToken);
    }

    function testHarvestRewardAfterTimes() public {
        vm.prank(tokenAdmin);
        mcs.add(address(vault), 1, rewarder);
        Utils.skipDay(false, vm);

        (uint256 aliceShares, ) = vault.shareBalances(alice);
        MasterChefUtils.addStakeDeposit(alice, aliceShares, address(vault), mcs, vm);

        // Collect data for test purpose
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs)); // 100

        Utils.skipDay(false, vm);

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfo.lastRewardTimestamp)).unwrap();

        (uint256 amount, uint256 rewardDebt, ) = mcs.userStakeInfo(address(vault), alice);

        vm.prank(alice);
        mcs.harvest(address(vault));
        /**
            smileeReward = (multiplier * smileePerSec * allocPoint / totalAllocPoint)
            pendingReward = amount * ((multiplier * smileePerSec * allocPoint / totalAllocPoint) / totalSupply)
            smileePerSec = 1
            allocPoint = 1
            totalAllocPoint = 1
            rewardDebt = 0
            pendingReward = amount * multiplier / totalAllocPoint
            amount = shareSupply -> only only deposit
            pendingReward = multiplier
        */
        uint256 expectedReward = ud(amount).mul(ud(multiplier)).div(convert(shareSupply)).sub(ud(rewardDebt)).unwrap();

        (, , uint256 rewardCollect) = mcs.userStakeInfo(address(vault), alice);

        assertEq(expectedReward, rewardCollect);
    }

    function testWithdrawRewardAfterTimes() public {
        vm.prank(tokenAdmin);
        mcs.add(address(vault), 1, rewarder);
        Utils.skipDay(false, vm);

        (uint256 aliceShares, ) = vault.shareBalances(alice);
        MasterChefUtils.addStakeDeposit(alice, aliceShares, address(vault), mcs, vm);
        assertEq(0, IERC20(vault).balanceOf(alice)); // assert balance after deposit

        // Collect data for test purpose
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs)); // 100

        Utils.skipDay(false, vm);

        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfo.lastRewardTimestamp)).unwrap();

        (uint256 amount, uint256 rewardDebt, ) = mcs.userStakeInfo(address(vault), alice);

        vm.prank(alice);
        mcs.withdraw(address(vault), convert(ud(amount)));
        /**
            smileeReward = (multiplier * smileePerSec * allocPoint / totalAllocPoint)
            pendingReward = amount * ((multiplier * smileePerSec * allocPoint / totalAllocPoint) / totalSupply)
            smileePerSec = 1
            allocPoint = 1
            totalAllocPoint = 1
            rewardDebt = 0
            pendingReward = amount * multiplier / totalAllocPoint
            amount = shareSupply -> only only deposit
            pendingReward = multiplier
        */
        uint256 expectedReward = ud(amount).mul(ud(multiplier)).div(convert(shareSupply)).sub(ud(rewardDebt)).unwrap();

        (, , uint256 rewardCollect) = mcs.userStakeInfo(address(vault), alice);

        assertEq(expectedReward, rewardCollect);
        assertEq(convert(ud(amount)), IERC20(vault).balanceOf(alice)); // assert balance after withdraw
    }

    // smileePerSec a 0 su una vault
    // smileePerSec a 0 su una vault con + vault
    // rewarderPerSec a 0
}
