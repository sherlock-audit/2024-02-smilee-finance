// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library TokensPair {
    struct Pair {
        address baseToken;
        address sideToken;
    }

    error AddressZero();
    error SameToken();
    error InvalidToken(address token);

    function getBalances(
        Pair calldata pair,
        address wallet
    ) external view returns (uint baseTokenBalance, uint sideTokenBalance) {
        baseTokenBalance = IERC20Metadata(pair.baseToken).balanceOf(wallet);
        sideTokenBalance = IERC20Metadata(pair.sideToken).balanceOf(wallet);
    }

    function getDecimals(Pair calldata pair) external view returns (uint baseTokenDecimals, uint sideTokenDecimals) {
        baseTokenDecimals = IERC20Metadata(pair.baseToken).decimals();
        sideTokenDecimals = IERC20Metadata(pair.sideToken).decimals();
    }

    function validate(Pair calldata pair) external view {
        if (pair.baseToken == address(0) || pair.sideToken == address(0)) {
            revert AddressZero();
        }
        if (pair.baseToken == pair.sideToken) {
            revert SameToken();
        }

        try IERC20Metadata(pair.baseToken).decimals() returns (uint8) {
            // no-op
        } catch {
            revert InvalidToken(pair.baseToken);
        }

        try IERC20Metadata(pair.sideToken).decimals() returns (uint8) {
            // no-op
        } catch {
            revert InvalidToken(pair.sideToken);
        }

        try IERC20Metadata(pair.baseToken).balanceOf(address(this)) returns (uint) {
            // no-op
        } catch {
            revert InvalidToken(pair.baseToken);
        }

        try IERC20Metadata(pair.sideToken).balanceOf(address(this)) returns (uint) {
            // no-op
        } catch {
            revert InvalidToken(pair.sideToken);
        }
    }
}
