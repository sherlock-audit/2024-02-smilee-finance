// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";

library AmountsMath {

    uint8 private constant _DECIMALS = 18;

    /// ERRORS ///

    error TooManyDecimals();

    /// LOGICS ///

    // @notice: takes a number and wrap it into a WAD
    function wrap(uint x) external pure returns (uint z) {
        UD60x18 wx = convert(x);
        return wx.unwrap();
    }

    // Sums two WAD numbers
    function add(uint x, uint y) external pure returns (uint z) {
        UD60x18 wx = ud(x);
        UD60x18 wy = ud(y);
        return wx.add(wy).unwrap();
    }

    // Subtract two WAD numbers
    function sub(uint x, uint y) external pure returns (uint z) {
        UD60x18 wx = ud(x);
        UD60x18 wy = ud(y);
        return wx.sub(wy).unwrap();
    }

    // Multiplies two WAD numbers
    function mul(uint x, uint y) external pure returns (uint z) {
        UD60x18 wx = ud(x);
        UD60x18 wy = ud(y);
        return wx.mul(wy).unwrap();
    }

    function wmul(uint x, uint y) external pure returns (uint z) {
        UD60x18 wx = ud(x);
        UD60x18 wy = ud(y);
        return wx.mul(wy).unwrap();
    }

    function wdiv(uint x, uint y) external pure returns (uint z) {
        UD60x18 wx = ud(x);
        UD60x18 wy = ud(y);
        return wx.div(wy).unwrap();
    }

    function wrapDecimals(uint256 amount, uint8 decimals) external pure returns (uint256) {
        if (decimals == _DECIMALS) {
            return amount;
        }
        if (decimals > _DECIMALS) {
            revert TooManyDecimals();
        }
        return amount * (10 ** (_DECIMALS - decimals));
    }

    function unwrapDecimals(uint256 amount, uint8 decimals) external pure returns (uint256) {
        if (decimals == _DECIMALS) {
            return amount;
        }
        return amount / (10 ** (_DECIMALS - decimals));
    }
}
