// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AmountsMath} from "./AmountsMath.sol";

library SignedMath {
    using AmountsMath for uint256;

    error Overflow(uint256 val);

    /// @dev Utility to safely cast a uint to a int
    function castInt(uint256 n) public pure returns (int256 z) {
        if (n > uint256(type(int256).max)) {
            revert Overflow(n);
        }
        return int256(n);
    }

    /// @dev Utility to square a signed value
    function pow2(int256 n) external pure returns (uint256 res) {
        res = abs(n);
        res = res.wmul(res);
    }

    /// @dev Utility to compute x^3
    function pow3(int256 n) external pure returns (int256) {
        uint256 res = abs(n);
        return revabs(res.wmul(res).wmul(res), n >= 0);
    }

    /// @dev Utility to negate an unsigned value
    function neg(uint256 n) external pure returns (int256 z) {
        return -castInt(n);
    }

    /// @dev Utility to sum an int and a uint into a uint, returning the abs value of the sum and the sign
    function sum(int256 a, uint256 b) external pure returns (uint256 q, bool p) {
        int256 s = a + castInt(b);
        q = abs(s);
        p = s >= 0;
    }

    /// @dev Returns the absolute unsigned value of a signed value, taken from OpenZeppelin SignedMath.sol
    function abs(int256 n) public pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }

    /// @dev Reverses an absolute unsigned value into an integer
    function revabs(uint256 n, bool p) internal pure returns (int256 z) {
        z = castInt(n);
        z = p ? z : -z;
    }
}
