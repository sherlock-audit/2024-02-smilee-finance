// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Amount, AmountHelper} from "@project/lib/Amount.sol";

contract AmountTest is Test {

    Amount ref;

    function testIncrease(uint256 refUp, uint256 refDown, uint256 up, uint256 down) public {
        vm.assume(refUp <= type(uint128).max);
        vm.assume(refDown <= type(uint128).max);
        vm.assume(up <= type(uint128).max);
        vm.assume(down <= type(uint128).max);
        vm.assume(refUp + up <= type(uint256).max);
        vm.assume(refDown + down <= type(uint256).max);

        ref = Amount({
            up: refUp,
            down: refDown
        });

        Amount memory delta = Amount({
            up: up,
            down: down
        });

        AmountHelper.increase(ref, delta);

        assertEq(refUp + up, ref.up);
        assertEq(refDown + down, ref.down);
    }

    function testDecrease(uint256 refUp, uint256 refDown, uint256 up, uint256 down) public {
        vm.assume(refUp >= up);
        vm.assume(refDown >= down);

        ref = Amount({
            up: refUp,
            down: refDown
        });

        Amount memory delta = Amount({
            up: up,
            down: down
        });

        AmountHelper.decrease(ref, delta);

        assertEq(refUp - up, ref.up);
        assertEq(refDown - down, ref.down);
    }
}
