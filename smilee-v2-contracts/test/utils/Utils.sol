// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";

library Utils {

    // TODO - avoid additionalSecond parameter (skip one second in setup())
    function skipDay(bool additionalSecond, Vm vm) external {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        vm.warp(block.timestamp + 1 days + secondToAdd);
    }

    function skipWeek(bool additionalSecond, Vm vm) external {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        vm.warp(block.timestamp + 7 days + secondToAdd);
    }

    // Bound a fuzzed value to a given range of values without losing impacting the limited iterations of vm.assume
    function boundFuzzedValueToRange(uint256 fuzzedValue, uint256 lower, uint256 upper) external pure returns (uint256) {
        return lower + (fuzzedValue % (upper - lower + 1));
    }

    /**
     * Function used to skip coverage on this file
     */
    function testCoverageSkip() private view {}
}
