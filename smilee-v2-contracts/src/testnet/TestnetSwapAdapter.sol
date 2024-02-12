// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IExchange} from "../interfaces/IExchange.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {AmountsMath} from "../lib/AmountsMath.sol";
import {SignedMath} from "../lib/SignedMath.sol";
import {TestnetToken} from "../testnet/TestnetToken.sol";

contract TestnetSwapAdapter is IExchange, Ownable {
    using AmountsMath for uint256;

    // Variables to simulate swap slippage (DEX fees and slippage together)
    // exact swap slippage (maybe randomly set at test setup or randomly changed during test), has the priority over the range
    int256 internal _exactSlippage; // 18 decimals
    // range to control a random slippage (between min and max) during a swap (see echidna tests)
    int256 internal _minSlippage; // 18 decimals
    int256 internal _maxSlippage; // 18 decimals

    IPriceOracle internal _priceOracle;

    error PriceZero();
    error TransferFailed();
    error InvalidSlippage();

    constructor(address priceOracle) Ownable() {
        _priceOracle = IPriceOracle(priceOracle);
    }

    function setSlippage(int256 exact, int256 min, int256 max) external onlyOwner {
        if (min > max || SignedMath.abs(exact) > 1e18 || SignedMath.abs(exact) > 1e18 || SignedMath.abs(exact) > 1e18) {
            revert InvalidSlippage();
        }
        _exactSlippage = exact;
        _minSlippage = min;
        _maxSlippage = max;
    }

    function changePriceOracle(address oracle) external onlyOwner {
        _priceOracle = IPriceOracle(oracle);
    }

    /// @inheritdoc IExchange
    function getOutputAmount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint) {
        return _getAmountOut(tokenIn, tokenOut, amountIn);
    }

    /// @inheritdoc IExchange
    function getInputAmount(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint) {
        return _getAmountIn(tokenIn, tokenOut, amountOut);
    }

    /// @inheritdoc IExchange
    function getInputAmountMax(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint) {
        uint256 amountIn = _getAmountIn(tokenIn, tokenOut, amountOut);
        uint256 amountInSlip = slipped(amountIn, true);
        return amountIn > amountInSlip ? amountIn : amountInSlip;
    }

    /// @inheritdoc ISwapAdapter
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        if (!IERC20Metadata(tokenIn).transferFrom(msg.sender, address(this), amountIn)) {
            revert TransferFailed();
        }
        amountOut = _getAmountOut(tokenIn, tokenOut, amountIn);
        amountOut = slipped(amountOut, false);

        TestnetToken(tokenIn).burn(address(this), amountIn);
        TestnetToken(tokenOut).mint(msg.sender, amountOut);
    }

    /// @inheritdoc ISwapAdapter
    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 preApprovedAmountIn
    ) external returns (uint256 amountIn) {
        amountIn = _getAmountIn(tokenIn, tokenOut, amountOut);
        amountIn = slipped(amountIn, true);

        if (amountIn > preApprovedAmountIn) {
            revert InsufficientInput();
        }

        if (!IERC20Metadata(tokenIn).transferFrom(msg.sender, address(this), amountIn)) {
            revert TransferFailed();
        }

        TestnetToken(tokenIn).burn(address(this), amountIn);
        TestnetToken(tokenOut).mint(msg.sender, amountOut);
    }

    function _getAmountOut(address tokenIn, address tokenOut, uint amountIn) internal view returns (uint) {
        uint tokenOutPrice = _priceOracle.getPrice(tokenIn, tokenOut);
        amountIn = AmountsMath.wrapDecimals(amountIn, IERC20Metadata(tokenIn).decimals());
        return AmountsMath.unwrapDecimals(amountIn.wmul(tokenOutPrice), IERC20Metadata(tokenOut).decimals());
    }

    function _getAmountIn(address tokenIn, address tokenOut, uint amountOut) internal view returns (uint) {
        uint tokenInPrice = _priceOracle.getPrice(tokenOut, tokenIn);

        if (tokenInPrice == 0) {
            // Otherwise could mint output tokens for free (no input needed).
            // It would be correct but we don't want to contemplate the 0 price case.
            revert PriceZero();
        }

        amountOut = AmountsMath.wrapDecimals(amountOut, IERC20Metadata(tokenOut).decimals());
        return AmountsMath.unwrapDecimals(amountOut.wmul(tokenInPrice), IERC20Metadata(tokenIn).decimals());
    }

    /// @dev "random" number for (testing purposes) between `min` and `max`
    function random(int256 min, int256 max) public view returns (int256) {
        uint256 rnd = block.timestamp;
        uint256 range = SignedMath.abs(max - min); // always >= 0
        if (rnd > 0) {
            return min + int256(rnd % range);
        }
        return min;
    }

    /// @dev returns the given `amount` slipped by a value (simulation of DEX fees and slippage by a percentage)
    function slipped(uint256 amount, bool directionOut) public view returns (uint256) {
        int256 slipPerc = _exactSlippage;

        if (_exactSlippage == 0) {
            if (_minSlippage == 0 && _maxSlippage == 0) {
                return amount;
            } else {
                slipPerc = random(_minSlippage, _maxSlippage);
            }
        }

        int256 out;
        if (directionOut) {
            out = (int256(amount) * (1e18 + slipPerc)) / 1e18;
        } else {
            out = (int256(amount) * (1e18 - slipPerc)) / 1e18;
        }
        if (out < 0) {
            out = 0;
        }

        return SignedMath.abs(out);
    }
}
