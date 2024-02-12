// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {EpochControls} from "@project/EpochControls.sol";

contract MockedEpochControls is EpochControls {
    uint256 public beforeRollCount;
    uint256 public afterRollCount;

    constructor(uint256 epochFrequency, uint256 firstEpochTimespan) EpochControls(epochFrequency, firstEpochTimespan) {
        beforeRollCount = 0;
        afterRollCount = 0;
    }

    function _beforeRollEpoch() internal virtual override {
        beforeRollCount++;
    }

    function _afterRollEpoch() internal virtual override {
        afterRollCount++;
    }

    function timeLimitedAction() external view {
        _checkEpochNotFinished();
    }

    function testCoverageSkip() public view {}
}

contract EpochControlsTest is Test {
    //// EpochFrequency reference timestamp: Friday 2023-04-21 08:00 UTC
    // EpochFrequency reference timestamp: Friday 2023-10-27 08:00 UTC
    uint256 public constant REF_TS = 1698393600; // 1682064000;

    // EpochFrequency.UnsupportedFrequency error
    bytes4 public constant ERR_UNSUPPORTED_FREQUENCY = bytes4(keccak256("UnsupportedFrequency()"));
    // EpochController.EpochNotFinished error
    bytes4 public constant ERR_EPOCH_NOT_FINISHED = bytes4(keccak256("EpochNotFinished()"));
    // EpochControls.EpochFinished error
    bytes4 public constant ERR_EPOCH_FINISHED = bytes4(keccak256("EpochFinished()"));

    // test initial state with unsupported zero frequencies
    function testInitialStateWithZeroFrequencies() public {
        vm.expectRevert(ERR_UNSUPPORTED_FREQUENCY);
        MockedEpochControls ec = new MockedEpochControls(0, 0);

        vm.expectRevert(ERR_UNSUPPORTED_FREQUENCY);
        ec = new MockedEpochControls(0, 1 days);

        vm.expectRevert(ERR_UNSUPPORTED_FREQUENCY);
        ec = new MockedEpochControls(1 days, 0);

        // vm.warp(REF_TS);
        ec = new MockedEpochControls(1 days, 1 days);
    }

    // test initial state with block.timestamp < REF_TS
    function testInitialStateBeforeReferenceTimestamp() public {
        vm.warp(REF_TS - 10 days);
        MockedEpochControls ec = new MockedEpochControls(7 days, 1 days);

        assertEq(0, ec.beforeRollCount());
        assertEq(0, ec.afterRollCount());

        Epoch memory epoch = ec.getEpoch();
        assertEq(7 days, epoch.frequency);
        assertEq(1 days, epoch.firstEpochTimespan);
        assertEq(0, epoch.previous);
        assertEq(0, epoch.numberOfRolledEpochs);
        // NOTE: the first epoch is extended to the REF_TS
        assertEq(REF_TS, epoch.current);
    }

    // test initial state with block.timestamp >= REF_TS
    function testInitialStateAfterReferenceTimestamp() public {
        vm.warp(REF_TS + 10 days);
        MockedEpochControls ec = new MockedEpochControls(7 days, 1 days);

        assertEq(0, ec.beforeRollCount());
        assertEq(0, ec.afterRollCount());

        Epoch memory epoch = ec.getEpoch();
        assertEq(7 days, epoch.frequency);
        assertEq(1 days, epoch.firstEpochTimespan);
        assertEq(0, epoch.previous);
        assertEq(0, epoch.numberOfRolledEpochs);
        assertEq(REF_TS + 10 days + 1 days, epoch.current);
    }

    // test roll epoch before epoch ends (must revert)
    function testRollEpochBeforeItsEnd() public {
        MockedEpochControls ec = new MockedEpochControls(7 days, 1 days);

        vm.expectRevert(ERR_EPOCH_NOT_FINISHED);
        ec.rollEpoch();
    }

    // test roll epoch (with block.timestamp >= REF_TS) soon after the epoch ends; repeat after the first one.
    function testRegularRollEpoch() public {
        // NOTE: the epochs are computed from the REF_TS, not the previous ones; hence the first two epochs can be shorter

        vm.warp(REF_TS + 10 days); // Fri 2023-05-01 08:00 UTC
        MockedEpochControls ec = new MockedEpochControls(28 days, 7 days);

        // First epoch shorter than the expected timespan (see NOTE):
        vm.warp(REF_TS + 7 days + 7 days + 1); // Fri 2023-05-05 08:00 UTC
        ec.rollEpoch();

        assertEq(1, ec.beforeRollCount());
        assertEq(1, ec.afterRollCount());

        Epoch memory epoch = ec.getEpoch();
        assertEq(28 days, epoch.frequency);
        assertEq(7 days, epoch.firstEpochTimespan);
        assertEq(REF_TS + 7 days + 7 days, epoch.previous);
        assertEq(1, epoch.numberOfRolledEpochs);
        assertEq(REF_TS + 28 days, epoch.current);

        vm.warp(REF_TS + 7 days + 7 days + 7 days + 1);
        vm.expectRevert(ERR_EPOCH_NOT_FINISHED);
        ec.rollEpoch();

        // Second epoch shorter than the frequency (see NOTE):
        vm.warp(REF_TS + 28 days + 1); // Fri 2023-05-19 08:00 UTC
        ec.rollEpoch();

        assertEq(2, ec.beforeRollCount());
        assertEq(2, ec.afterRollCount());

        epoch = ec.getEpoch();
        assertEq(REF_TS + 28 days, epoch.previous);
        assertEq(2, epoch.numberOfRolledEpochs);
        assertEq(REF_TS + 28 days + 28 days, epoch.current);

        // Third epoch with standard frequency:
        vm.warp(REF_TS + 28 days + 28 days + 1); // Fri 2023-06-16 08:00 UTC
        ec.rollEpoch();

        assertEq(3, ec.beforeRollCount());
        assertEq(3, ec.afterRollCount());

        epoch = ec.getEpoch();
        assertEq(REF_TS + 28 days + 28 days, epoch.previous);
        assertEq(3, epoch.numberOfRolledEpochs);
        assertEq(epoch.previous + 28 days, epoch.current);
    }

    // test roll epoch (with block.timestamp >= REF_TS) when one epoch was skipped
    function testSkippedEpoch() public {
        vm.warp(REF_TS + 10 days);
        MockedEpochControls ec = new MockedEpochControls(7 days, 7 days);

        // Roll the first epoch:
        vm.warp(REF_TS + 7 days + 7 days + 1);
        ec.rollEpoch();

        Epoch memory epoch = ec.getEpoch();
        assertEq(REF_TS + 7 days + 7 days, epoch.previous);
        assertEq(REF_TS + 7 days + 7 days + 7 days, epoch.current);
        assertEq(1, epoch.numberOfRolledEpochs);

        // Skip the second epoch:
        vm.warp(REF_TS + 7 days + 7 days + 7 days);

        // Roll on the theoretical third epoch:
        vm.warp(REF_TS + 7 days + 7 days + 7 days + 7 days + 1);
        ec.rollEpoch();

        epoch = ec.getEpoch();
        assertEq(REF_TS + 7 days + 7 days + 7 days, epoch.previous);
        assertEq(REF_TS + 7 days + 7 days + 7 days + 7 days + 7 days, epoch.current);
        assertEq(2, epoch.numberOfRolledEpochs);
        assertEq(2, ec.beforeRollCount());
        assertEq(2, ec.afterRollCount());
    }

    // test roll epoch (with block.timestamp >= REF_TS) when the first one epoch was skipped
    function testSkippedFirstEpoch() public {
        vm.warp(REF_TS + 10 days);
        MockedEpochControls ec = new MockedEpochControls(7 days, 1 days);

        Epoch memory epoch = ec.getEpoch();
        assertEq(REF_TS + 10 days + 1 days, epoch.current);

        // Skip first epoch:
        vm.warp(REF_TS + 10 days + 1 days);

        // Roll on the theoretical second epoch:
        vm.warp(REF_TS + 7 days + 7 days + 1);
        ec.rollEpoch();

        epoch = ec.getEpoch();
        assertEq(REF_TS + 10 days + 1 days, epoch.previous);
        assertEq(REF_TS + 7 days + 7 days + 7 days, epoch.current);
        assertEq(1, epoch.numberOfRolledEpochs);
        assertEq(1, ec.beforeRollCount());
        assertEq(1, ec.afterRollCount());
    }
}
