// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {TimeLock, TimeLockedAddress} from "@project/lib/TimeLock.sol";

contract TimeLockTest is Test {
    using TimeLock for TimeLockedAddress;

    TimeLockedAddress lockedAddr;

    function testAddress() public {
        address zero = address(0);
        address value = address(16);
        address anotherValue = address(256);
        uint256 delay = 1 days;

        // The container starts with the zero value of the given type:
        assertEq(zero, lockedAddr.safe);
        assertEq(zero, lockedAddr.proposed);
        assertEq(0, lockedAddr.validFrom);

        // The first set is assumed to be safe, regardless of the delay:
        lockedAddr.set(value, delay);
        assertEq(value, lockedAddr.safe);
        assertEq(value, lockedAddr.proposed);
        assertEq(block.timestamp + delay, lockedAddr.validFrom);
        assertEq(value, lockedAddr.get());

        // Any other set will be considered as a proposal:
        lockedAddr.set(anotherValue, delay);
        assertEq(value, lockedAddr.safe);
        assertEq(anotherValue, lockedAddr.proposed);
        assertEq(block.timestamp + delay, lockedAddr.validFrom);
        assertEq(value, lockedAddr.get());

        // Internally, the proposed value is considered as-is up to its validity time:
        vm.warp(lockedAddr.validFrom - 1);
        assertEq(value, lockedAddr.get());
        vm.warp(lockedAddr.validFrom);
        assertEq(anotherValue, lockedAddr.get());

        // Internally, the safe attribute is updated only when a set is performed:
        assertEq(value, lockedAddr.safe);
        assertEq(anotherValue, lockedAddr.proposed);
        lockedAddr.set(zero, delay);
        assertEq(anotherValue, lockedAddr.safe);
        assertEq(zero, lockedAddr.proposed);

        // Another set resets the previous proposal and the validity time:
        assertEq(block.timestamp + delay, lockedAddr.validFrom);
        uint256 nearFuture = block.timestamp + 3600;
        vm.warp(nearFuture);
        lockedAddr.set(value, delay);
        assertEq(value, lockedAddr.proposed);
        assertEq(block.timestamp + delay, lockedAddr.validFrom);

        // Despire the multiple calls to set, the safe value is still the right one:
        assertEq(anotherValue, lockedAddr.get());
    }
}
