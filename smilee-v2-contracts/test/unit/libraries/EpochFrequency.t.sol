// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";

contract EpochFrequencyTest is Test {
    // Frequencies:
    uint256 constant dailyPeriod = EpochFrequency.DAILY;
    uint256 constant weeklyPeriod = EpochFrequency.WEEKLY;
    uint256 constant fourWeeksPeriod = EpochFrequency.FOUR_WEEKS;

    // Reference timestamp:
    uint256 constant referenceTime = EpochFrequency.REF_TS;

    // Errors:
    bytes4 constant ERR_UNSUPPORTED_FREQUENCY = bytes4(keccak256("UnsupportedFrequency()"));

    function testUnsupportedFrequency() public {
        uint256 unsupportedFrequency = 0;

        vm.expectRevert(ERR_UNSUPPORTED_FREQUENCY);
        EpochFrequency.nextExpiry(referenceTime, unsupportedFrequency);
        vm.expectRevert(ERR_UNSUPPORTED_FREQUENCY);
        EpochFrequency.nextExpiry(referenceTime - 1, unsupportedFrequency);
        vm.expectRevert(ERR_UNSUPPORTED_FREQUENCY);
        EpochFrequency.nextExpiry(referenceTime + 1, unsupportedFrequency);
    }

    /**
     * If the current expiry is before the reference one, whatever the (valid) frequency,
     * the next expiry is the reference one.
     */
    function testBehaviourBeforeReferenceTimestamp() public {
        assertEq(referenceTime, EpochFrequency.nextExpiry(referenceTime - 1, dailyPeriod));
        assertEq(referenceTime, EpochFrequency.nextExpiry(referenceTime - 1, weeklyPeriod));
        assertEq(referenceTime, EpochFrequency.nextExpiry(referenceTime - 1, fourWeeksPeriod));
    }

    function testDaily() public {
        uint256 saturday = referenceTime + dailyPeriod;
        uint256 sunday = referenceTime + (2 * dailyPeriod);

        // The next expiry is the next window, regardless of the exact starting time:
        assertEq(saturday, EpochFrequency.nextExpiry(referenceTime, dailyPeriod));
        assertEq(saturday, EpochFrequency.nextExpiry(referenceTime + 1, dailyPeriod));

        // Checks that everything works as expected even with following ones:
        assertEq(sunday, EpochFrequency.nextExpiry(saturday, dailyPeriod));
    }

    function testWeekly() public {
        uint256 fridayOneWeek = referenceTime + weeklyPeriod;
        uint256 fridayTwoWeeks = referenceTime + (2 * weeklyPeriod);

        // The next expiry is the next window, regardless of the exact starting time:
        assertEq(fridayOneWeek, EpochFrequency.nextExpiry(referenceTime, weeklyPeriod));
        assertEq(fridayOneWeek, EpochFrequency.nextExpiry(referenceTime + 1, weeklyPeriod));

        // Checks that everything works as expected even with following ones:
        assertEq(fridayTwoWeeks, EpochFrequency.nextExpiry(fridayOneWeek, weeklyPeriod));
    }

    function testMonthly() public {
        uint256 fridayOneMonth = referenceTime + fourWeeksPeriod;
        uint256 fridayTwoMonths = referenceTime + (2 * fourWeeksPeriod);

        // The next expiry is the next window, regardless of the exact starting time:
        assertEq(fridayOneMonth, EpochFrequency.nextExpiry(referenceTime, fourWeeksPeriod));
        assertEq(fridayOneMonth, EpochFrequency.nextExpiry(referenceTime + 1, fourWeeksPeriod));

        // Checks that everything works as expected even with following ones:
        assertEq(fridayTwoMonths, EpochFrequency.nextExpiry(fridayOneMonth, fourWeeksPeriod));
    }
}
