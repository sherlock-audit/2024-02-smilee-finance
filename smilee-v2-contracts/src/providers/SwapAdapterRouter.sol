// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IExchange} from "../interfaces/IExchange.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ISwapAdapter} from "../interfaces/ISwapAdapter.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TimeLock, TimeLockedAddress, TimeLockedUInt} from "@project/lib/TimeLock.sol";

/**
    @title A simple contract delegated to exchange selection for token pairs swap

    This contract is meant to reference a Chainlink oracle and check the swaps against
    the oracle prices, accepting a maximum slippage that can be set for every pair.
 */
contract SwapAdapterRouter is IExchange, AccessControl {
    using SafeERC20 for IERC20Metadata;
    using TimeLock for TimeLockedAddress;
    using TimeLock for TimeLockedUInt;

    uint256 public timeLockDelay;
    // mapping from hash(tokenIn.address + tokenOut.address) to the exchange to use
    mapping(bytes32 => TimeLockedAddress) private _adapters;
    // maximum accepted slippage during a swap for each swap pair, denominated in wad (1e18 = 100%)
    mapping(bytes32 => TimeLockedUInt) private _slippage;
    // address of the Chainlink dollar price oracle
    IAddressProvider private _ap;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    error AddressZero();
    error Slippage();
    error SwapZero();
    error OutOfAllowedRange();

    event ChangedAdapter(address tokenIn, address tokenOut, address adapter);
    event ChangedSlippage(address tokenIn, address tokenOut, uint256 slippage);

    constructor(address addressProvider, uint256 timeLockDelay_) AccessControl() {
        _zeroAddressCheck(addressProvider);
        _ap = IAddressProvider(addressProvider);

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
        timeLockDelay = timeLockDelay_;
    }

    /**
        @notice Returns the adapter to use for a pair of tokens
        @param tokenIn The address of the input token of the swap
        @param tokenOut The address of the output token of the swap
        @return adapter The address of the adapter to use for the swap
     */
    function getAdapter(address tokenIn, address tokenOut) external view returns (address adapter) {
        return _adapters[_encodePath(tokenIn, tokenOut)].get();
    }

    /**
        @notice Returns the slippage parameter for a given tokens pair swap
        @param tokenIn The address of the input token of the swap
        @param tokenOut The address of the output token of the swap
        @return slippage The maximum accepted slippage for the swap
     */
    function getSlippage(address tokenIn, address tokenOut) public view returns (uint256 slippage) {
        slippage = _slippage[_encodePath(tokenIn, tokenOut)].get();

        // Default baseline value:
        if (slippage == 0) {
            return 0.02e18;
        }
    }

    /**
        @notice Sets a adapter to use for a pair of tokens
        @param tokenIn The address of the input token of the swap
        @param tokenOut The address of the output token of the swap
        @param adapter The address of the adapter to use for the swap
     */
    function setAdapter(address tokenIn, address tokenOut, address adapter) external {
        _checkRole(ROLE_ADMIN);
        _zeroAddressCheck(adapter);

        _adapters[_encodePath(tokenIn, tokenOut)].set(adapter, timeLockDelay);

        emit ChangedAdapter(tokenIn, tokenOut, adapter);
    }

    /**
        @notice Sets a slippage parameter for a given tokens pair swap
        @param tokenIn The address of the input token of the swap
        @param tokenOut The address of the output token of the swap
        @param slippage The maximum accepted slippage for the swap in wad (1e18 = 100%)
     */
    function setSlippage(address tokenIn, address tokenOut, uint256 slippage) external {
        _checkRole(ROLE_ADMIN);

        if (slippage < 0.005e18 || slippage > 0.1e18) {
            revert OutOfAllowedRange();
        }

        _slippage[_encodePath(tokenIn, tokenOut)].set(slippage, timeLockDelay);

        emit ChangedSlippage(tokenIn, tokenOut, slippage);
    }

    /**
        @inheritdoc IExchange
        @dev We are ignoring exchange fees
     */
    function getOutputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint amountOut) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        return _valueOut(tokenIn, tokenOut, amountIn);
    }

    /**
        @inheritdoc IExchange
        @dev We are ignoring exchange fees
     */
    function getInputAmount(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view override returns (uint amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        return _valueIn(tokenIn, tokenOut, amountOut);
    }

    /// @inheritdoc IExchange
    function getInputAmountMax(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view override returns (uint amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        (amountIn, ) = _slippedValueIn(tokenIn, tokenOut, amountOut);
    }

    /// @inheritdoc ISwapAdapter
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        address adapter = _adapters[_encodePath(tokenIn, tokenOut)].get();
        _zeroAddressCheck(adapter);

        (uint256 amountOutMin, uint256 amountOutMax) = _slippedValueOut(tokenIn, tokenOut, amountIn);

        IERC20Metadata(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20Metadata(tokenIn).safeApprove(adapter, amountIn);
        amountOut = ISwapAdapter(adapter).swapIn(tokenIn, tokenOut, amountIn);

        if (amountOut == 0) {
            revert SwapZero();
        }

        if (amountOut < amountOutMin || amountOut > amountOutMax) {
            revert Slippage();
        }

        IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountOut);
    }

    /// @inheritdoc ISwapAdapter
    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 preApprovedAmountIn
    ) external returns (uint256 amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);
        address adapter = _adapters[_encodePath(tokenIn, tokenOut)].get();
        _zeroAddressCheck(adapter);

        (uint256 amountInMax, uint256 amountInMin) = _slippedValueIn(tokenIn, tokenOut, amountOut);

        IERC20Metadata(tokenIn).safeTransferFrom(msg.sender, address(this), preApprovedAmountIn);
        IERC20Metadata(tokenIn).safeApprove(adapter, preApprovedAmountIn);
        amountIn = ISwapAdapter(adapter).swapOut(tokenIn, tokenOut, amountOut, preApprovedAmountIn);

        if (amountIn < amountInMin || amountIn > amountInMax) {
            revert Slippage();
        }

        IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountOut);

        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender
        // Also reset approval in any case
        IERC20Metadata(tokenIn).safeApprove(adapter, 0);
        if (amountIn < preApprovedAmountIn) {
            IERC20Metadata(tokenIn).safeTransfer(msg.sender, preApprovedAmountIn - amountIn);
        }
    }

    /**
        @notice Reverts if a given address is the zero address
        @param a The address to check
     */
    function _zeroAddressCheck(address a) private pure {
        if (a == address(0)) {
            revert AddressZero();
        }
    }

    /**
        @notice Produces a unique key to address the pair <tokenIn, tokenOut>
        @param tokenIn The address of tokenIn
        @param tokenOut The address of tokenOut
        @return pathKey The hash of the pair
     */
    function _encodePath(address tokenIn, address tokenOut) private pure returns (bytes32 pathKey) {
        pathKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    /**
        @notice Gets the output amount given an input amount at current oracle price
        @param tokenIn The input token address
        @param tokenOut The output token address
        @param amountIn The input amount, denominated in input token
        @return amountOut The output amount, denominated in output token
     */
    function _valueOut(address tokenIn, address tokenOut, uint256 amountIn) private view returns (uint256 amountOut) {
        IPriceOracle po = IPriceOracle(_ap.priceOracle());
        uint256 price = po.getPrice(tokenIn, tokenOut);
        uint8 dIn = IERC20Metadata(tokenIn).decimals();
        uint8 dOut = IERC20Metadata(tokenOut).decimals();
        amountOut = price * amountIn;
        amountOut = dOut > dIn ? amountOut * 10 ** (dOut - dIn) : amountOut / 10 ** (dIn - dOut);
        amountOut = amountOut / 10 ** 18;
    }

    /**
        @notice Gets the input amount given an output amount at current oracle price
        @param tokenIn The input token address
        @param tokenOut The output token address
        @param amountOut The output amount, denominated in output token
        @return amountIn The input amount, denominated in input token
     */
    function _valueIn(address tokenIn, address tokenOut, uint256 amountOut) private view returns (uint256 amountIn) {
        IPriceOracle po = IPriceOracle(_ap.priceOracle());
        uint256 price = po.getPrice(tokenOut, tokenIn);
        uint8 dIn = IERC20Metadata(tokenIn).decimals();
        uint8 dOut = IERC20Metadata(tokenOut).decimals();
        amountIn = price * amountOut;
        amountIn = dIn > dOut ? amountIn * 10 ** (dIn - dOut) : amountIn / 10 ** (dOut - dIn);
        amountIn = amountIn / 10 ** 18;
    }

    /**
        @notice Gets the <min, max> range for output amount given an input amount
        @param tokenIn The input token address
        @param tokenOut The output token address
        @param amountIn The input amount, denominated in input token
        @return amountOutMin The minimum output amount, denominated in output token
        @return amountOutMax The maximum output amount, denominated in input token
     */
    function _slippedValueOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (uint256 amountOutMin, uint256 amountOutMax) {
        uint256 amountOut = _valueOut(tokenIn, tokenOut, amountIn);
        amountOutMin = (amountOut * (1e18 - getSlippage(tokenIn, tokenOut))) / 1e18;
        amountOutMax = (amountOut * (1e18 + getSlippage(tokenIn, tokenOut))) / 1e18;
    }

    /**
        @notice Gets the <max, min> range input amount given an output amount
        @param tokenIn The input token address
        @param tokenOut The output token address
        @param amountOut The output amount, denominated in output token
        @return amountInMax The maximum input amount, denominated in input token
        @return amountInMin The minimum input amount, denominated in input token
     */
    function _slippedValueIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) private view returns (uint256 amountInMax, uint256 amountInMin) {
        uint256 amountIn = _valueIn(tokenIn, tokenOut, amountOut);
        amountInMax = (amountIn * (1e18 + getSlippage(tokenIn, tokenOut))) / 1e18;
        amountInMin = (amountIn * (1e18 - getSlippage(tokenIn, tokenOut))) / 1e18;
    }
}
