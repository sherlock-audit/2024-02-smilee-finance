// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
    @title Simple library to manage DVPs epoch rolls.
 */
library EpochFrequency {
    /// @notice Friday 2023-10-27 08:00 UTC
    uint256 public constant REF_TS = 1698393600;

    uint256 public constant DAILY = 1 days;
    uint256 public constant WEEKLY = 7 days;
    uint256 public constant FOUR_WEEKS = 28 days;

    error UnsupportedFrequency();

    /**
        @dev A zero frequency is most likely a client error
     */
    function validityCheck(uint256 epochFrequency) public pure {
        if (epochFrequency == 0) {
            revert UnsupportedFrequency();
        }
    }

    /**
        @notice Get the next timestamp in the given frequency sequence wrt the given ts
        @param ts The timestamp to fetch expiry for
        @param frequency The frequency of the sequence, chosen from the available ones
     */
    function nextExpiry(uint256 ts, uint256 frequency) public pure returns (uint256 expiry) {
        validityCheck(frequency);

        expiry = _nextTimeSpanExpiry(ts, frequency);
    }

    /**
        @notice Compute the next expiry
        @param ts The timestamp to fetch expiry for
        @param timeSpan The number of seconds in the timespan
        @return nextExpiry_ The timestamp for the next epoch expiry
        @dev It's the next nearest (to `ts` and in the future) `timeSpan` checkpoint using `REF_TS` as reference for counting them.
     */
    function _nextTimeSpanExpiry(uint256 ts, uint256 timeSpan) private pure returns (uint256 nextExpiry_) {
        if (ts < REF_TS) {
            return REF_TS;
        }

        return REF_TS + _upDiv(ts - REF_TS, timeSpan) * timeSpan;
    }

    /**
        @notice Rounds up n / d adding 1 in case n / d = 0
        @dev This gives the next timestamp index even when remainder is 0
     */
    function _upDiv(uint n, uint d) private pure returns (uint256) {
        return n / d + 1;
    }
}
