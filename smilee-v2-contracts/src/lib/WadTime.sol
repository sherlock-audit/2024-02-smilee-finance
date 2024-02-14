// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ud, convert} from "@prb/math/UD60x18.sol";

/// @title Time utils to compute years or days in WAD
library WadTime {

    error InvalidInput();

    /**
        @notice Gives the number of days corresponding to a given period
        @param start The starting timestamp of the reference period
        @param end The end timestamp of the reference period
        @return ndays The number of days between start and end in WAD
     */
    function _daysFromTs(uint256 start, uint256 end) private pure returns (uint256 ndays) {
        if (start > end) {
            revert InvalidInput();
        }
        ndays = convert(end - start).div(convert(1 days)).unwrap();
    }

    /**
        @notice Gives the number of years corresponding to the given number of days
        @param d The number of days in WAD
        @return nYears_ number of years in WAD
     */
    function nYears(uint256 d) public pure returns (uint256 nYears_) {
        nYears_ = ud(d).div(convert(365)).unwrap();
    }

    function yearsToTimestamp(uint256 timestamp) external view returns (uint256 years_) {
        years_ = rangeInYears(block.timestamp, timestamp);
    }

    function rangeInYears(uint256 start, uint256 end) public pure returns (uint256 years_) {
        years_ = nYears(_daysFromTs(start, end));
    }
}
