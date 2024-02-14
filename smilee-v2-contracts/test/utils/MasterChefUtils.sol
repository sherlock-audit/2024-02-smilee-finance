// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {MockedVault} from "../mock/MockedVault.sol";
import {MasterChefSmilee} from "@project/periphery/MasterChefSmilee.sol";
import {SimpleRewarderPerSec} from "@project/periphery/SimpleRewarderPerSec.sol";


library MasterChefUtils {

    function addStakeDeposit(address user, uint256 amount, address vaultAddress, MasterChefSmilee mcs, Vm vm) internal {
        MockedVault vault = MockedVault(vaultAddress);
        vm.startPrank(user);
        vault.approve(address(mcs), amount);
        mcs.deposit(address(vault), amount);
        vm.stopPrank();
    }
}
