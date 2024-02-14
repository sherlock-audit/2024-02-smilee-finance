// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Setup} from "./Setup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MasterChefSmilee} from "@project/periphery/MasterChefSmilee.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Properties} from "./Properties.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties {
    event Debug(string, uint256);

    bool internal _vaultAdded;

    function setup() internal virtual override {
        deploy();
    }

    //----------------------------------------------
    // ADMIN OPs.
    //----------------------------------------------

    function addStakingVault(uint256 allocPoint) public {
        allocPoint = _between(allocPoint, 1, type(uint256).max - 1);

        mcs.add(address(vault), allocPoint, rewarder);
        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        eq(0, vaultInfo.accSmileePerShare, "");

        _vaultAdded = true;
    }

    //----------------------------------------------
    // USER OPs.
    //----------------------------------------------

    function deposit(uint256 depositAmount) public {
        precondition(_vaultAdded);

        uint256 initialBalance = IERC20(vault).balanceOf(depositor);
        depositAmount = _between(depositAmount, 1, initialBalance);

        _stake(depositor, depositAmount);

        eq(IERC20(vault).balanceOf(depositor), initialBalance - depositAmount, "");

        uint256 expectedRewardSupply = _rewardSupply();
        lte(expectedRewardSupply, mcs.rewardSupply(), STK_1);
    }

    function pendingReward() public {
        precondition(_vaultAdded);
        uint256 expectedPendingReward = _reward(depositor);
        (uint256 pendingRewardToken, , ) = mcs.pendingTokens(address(vault), depositor);
        lte(expectedPendingReward, pendingRewardToken, STK_2);
    }

    function harvest() public {
        precondition(_vaultAdded);

        hevm.prank(depositor);
        mcs.harvest(address(vault));

        uint256 expectedReward = _reward(depositor);
        (, , uint256 rewardCollect) = mcs.userStakeInfo(address(vault), depositor);
        lte(expectedReward, rewardCollect, STK_3);
    }

    function withdraw() public {
        precondition(_vaultAdded);

        uint256 depositorInitialBalance = IERC20(vault).balanceOf(depositor);
        (uint256 amount, , ) = mcs.userStakeInfo(address(vault), depositor);

        hevm.prank(depositor);
        mcs.withdraw(address(vault), convert(ud(amount)));

        uint256 expectedReward = _reward(depositor);
        (, , uint256 rewardCollect) = mcs.userStakeInfo(address(vault), depositor);
        lte(expectedReward, rewardCollect, STK_3);

        uint256 expectedFinalShareBalance = convert(ud(amount).add(convert(depositorInitialBalance)));
        eq(expectedFinalShareBalance, IERC20(vault).balanceOf(depositor), STK_4); // assert share balance after withdraw
    }

    //----------------------------------------------
    // COMMON
    //----------------------------------------------

    function _stake(address user, uint256 amount) internal {
        hevm.prank(user);
        vault.approve(address(mcs), amount);
        hevm.prank(user);
        mcs.deposit(address(vault), amount);
    }

    function _rewardSupply() internal view returns (uint256 expectedRewardSupply) {
        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        uint256 multiplier = convert(block.timestamp).sub(convert(vaultInfo.lastRewardTimestamp)).unwrap();

        expectedRewardSupply = ud(multiplier)
            .mul(convert(smileePerSec))
            .mul(convert(vaultInfo.allocPoint))
            .div(ud(mcs.totalAllocPoint()))
            .unwrap();
    }

    function _reward(address user) internal view returns (uint256 expectedReward) {
        uint256 shareSupply = IERC20(vault).balanceOf(address(mcs));
        (uint256 amount, uint256 rewardDebt, ) = mcs.userStakeInfo(address(vault), user);

        uint256 expectedRewardSupply = _rewardSupply();
        MasterChefSmilee.VaultInfo memory vaultInfo = mcs.getVaultInfo(address(vault));
        uint256 accSmileePerShare = ud(vaultInfo.accSmileePerShare)
            .add(ud(expectedRewardSupply).div(convert(shareSupply)))
            .unwrap();

        expectedReward = ud(amount).mul(ud(accSmileePerShare)).sub(ud(rewardDebt)).unwrap();
    }
}
