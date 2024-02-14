// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {WadTime} from "@project/lib/WadTime.sol";

contract WadTimeLibTest is Test {
    bytes4 constant ERR_INVALID_INPUT = bytes4(keccak256("InvalidInput()"));

    function testYearsToTimestamp() public {
        uint256 target = block.timestamp + 365 days;

        uint256 yearsToTime = WadTime.yearsToTimestamp(target);
        assertEq(1e18, yearsToTime);

        uint256 currentTime = block.timestamp + 26 weeks + 12 hours;
        vm.warp(currentTime);
        yearsToTime = WadTime.yearsToTimestamp(target);
        assertEq(0.5e18, yearsToTime);

        vm.warp(target);
        yearsToTime = WadTime.yearsToTimestamp(target);
        assertEq(0, yearsToTime);

        // The target must be in the future (or now):
        vm.warp(target + 1);
        vm.expectRevert(ERR_INVALID_INPUT);
        WadTime.yearsToTimestamp(target);
    }
}
