// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {ISwapAdapter} from "../../interfaces/ISwapAdapter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {Path} from "./lib/Path.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {TimeLock, TimeLockedBool, TimeLockedBytes} from "@project/lib/TimeLock.sol";

/**
    @title UniswapAdapter
    @notice A simple adapter to connect with uniswap pools.

    By default tries to swap <tokenIn, tokenOut> on the direct pool with 0.05% fees.
    If a custom path is set for the the pair <tokenIn, tokenOut> uses that one.
    A custom path can be set only if it contains multiple pools.
 */
contract UniswapAdapter is ISwapAdapter, AccessControl {
    using Path for bytes;
    using TimeLock for TimeLockedBool;
    using TimeLock for TimeLockedBytes;

    uint256 private _timeLockDelay;

    uint256 constant _MIN_PATH_LEN = 43; // direct
    uint256 constant _MAX_PATH_LEN = 66; // 1 hop

    // Fees for LP Single
    uint24 constant _DEFAULT_FEE = 500; // 0.05% (hundredths of basis points)
    uint160 private constant _SQRTPRICELIMITX96 = 0;

    // Ref. to the Uniswap router to make swaps
    ISwapRouter internal immutable _swapRouter;
    // Ref. to the Uniswap factory to find pools
    IUniswapV3Factory internal immutable _factory;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    struct TimeLockedSwapPath {
        TimeLockedBool exists;
        TimeLockedBytes data; // Bytes of the path, structured in abi.encodePacked(TOKEN1, POOL_FEE, TOKEN2, POOL_FEE_1,....)
        TimeLockedBytes reverseData; // Bytes of the reverse path for swapOut multihop (https://docs.uniswap.org/contracts/v3/guides/swaps/multihop-swaps)
    }

    // bytes32 => Hash of tokenIn and tokenOut concatenated
    mapping(bytes32 => TimeLockedSwapPath) private _swapPaths;

    error AddressZero();
    error InvalidPath();
    error PathNotSet();
    error PoolDoesNotExist();
    error NotImplemented();

    event PathSet(address tokenIn, address tokenOut, bytes path);
    event PathUnset(address tokenIn, address tokenOut);

    constructor(address swapRouter, address factory, uint256 timeLockDelay) AccessControl() {
        _swapRouter = ISwapRouter(swapRouter);
        _factory = IUniswapV3Factory(factory);

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
        _timeLockDelay = timeLockDelay;
    }

    /**
        @notice Checks if the path is valid and inserts it into the map
        @param path Path data to insert into a map
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
     */
    function setPath(bytes memory path, address tokenIn, address tokenOut) public {
        _checkRole(ROLE_ADMIN);
        _checkPath(path, tokenIn, tokenOut);

        bytes memory reversePath = _reversePath(path);

        _swapPaths[_encodePair(tokenIn, tokenOut)].exists.set(true, _timeLockDelay);
        _swapPaths[_encodePair(tokenIn, tokenOut)].data.set(path, _timeLockDelay);
        _swapPaths[_encodePair(tokenIn, tokenOut)].reverseData.set(reversePath, _timeLockDelay);

        emit PathSet(tokenIn, tokenOut, path);
    }

    /**
        @notice Unsets the path for the given token pair
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
     */
    function unsetPath(address tokenIn, address tokenOut) public {
        _checkRole(ROLE_ADMIN);

        _swapPaths[_encodePair(tokenIn, tokenOut)].exists.set(false, _timeLockDelay);
        // delete _swapPaths[_encodePair(tokenIn, tokenOut)];

        emit PathUnset(tokenIn, tokenOut);
    }

    /**
        @notice Returns the path used by the contract to swap the given pair
        @dev May revert if no path is set and default pool does not exist
        @param tokenIn The address of the input token
        @param tokenOut The address of the output token
        @param reversed True if you want to see the reversed path
        @return path The custom path set for the pair or the default path if it exists
     */
    function getPath(address tokenIn, address tokenOut, bool reversed) public view returns (bytes memory path) {
        if (_swapPaths[_encodePair(tokenIn, tokenOut)].exists.get()) {
            if (reversed) {
                return _swapPaths[_encodePair(tokenIn, tokenOut)].reverseData.get();
            }
            return _swapPaths[_encodePair(tokenIn, tokenOut)].data.get();
        } else {
            // return default path
            path = abi.encodePacked(reversed ? tokenOut : tokenIn, _DEFAULT_FEE, reversed ? tokenIn : tokenOut);
            _checkPath(path, reversed ? tokenOut : tokenIn, reversed ? tokenIn : tokenOut);
            return path;
        }
    }

    /// @inheritdoc ISwapAdapter
    function swapIn(address tokenIn, address tokenOut, uint256 amountIn) public returns (uint256 tokenOutAmount) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(_swapRouter), amountIn);

        TimeLockedSwapPath storage path = _swapPaths[_encodePair(tokenIn, tokenOut)];
        tokenOutAmount = path.exists.get()
            ? _swapInPath(path.data.get(), amountIn)
            : _swapInSingle(tokenIn, tokenOut, amountIn);
    }

    /// @inheritdoc ISwapAdapter
    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 preApprovedInput
    ) public returns (uint256 amountIn) {
        _zeroAddressCheck(tokenIn);
        _zeroAddressCheck(tokenOut);

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), preApprovedInput);
        TransferHelper.safeApprove(tokenIn, address(_swapRouter), preApprovedInput);

        TimeLockedSwapPath storage path = _swapPaths[_encodePair(tokenIn, tokenOut)];
        amountIn = path.exists.get()
            ? _swapOutPath(path.reverseData.get(), amountOut, preApprovedInput)
            : _swapOutSingle(tokenIn, tokenOut, amountOut, preApprovedInput);

        // refund difference to caller
        if (amountIn < preApprovedInput) {
            uint256 amountToReturn = preApprovedInput - amountIn;
            TransferHelper.safeApprove(tokenIn, address(_swapRouter), 0);
            TransferHelper.safeTransfer(tokenIn, msg.sender, amountToReturn);
        }
    }

    /// @dev Swap tokens given the input amount using the direct pool with default fee
    function _swapInSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private returns (uint256 tokenOutAmount) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            tokenIn,
            tokenOut,
            _DEFAULT_FEE,
            msg.sender,
            block.timestamp,
            amountIn,
            0,
            _SQRTPRICELIMITX96
        );

        tokenOutAmount = _swapRouter.exactInputSingle(params);
    }

    /// @dev Swap tokens given the input amount using the saved path
    function _swapInPath(bytes memory path, uint256 amountIn) private returns (uint256 tokenOutAmount) {
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams(
            path,
            msg.sender,
            block.timestamp,
            amountIn,
            0
        );

        tokenOutAmount = _swapRouter.exactInput(params);
    }

    /// @dev Swap tokens given the output amount using the direct pool with default fee
    function _swapOutSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountMaximumIn
    ) private returns (uint256 amountIn) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
            tokenIn,
            tokenOut,
            _DEFAULT_FEE,
            msg.sender,
            block.timestamp,
            amountOut,
            amountMaximumIn,
            _SQRTPRICELIMITX96
        );

        amountIn = _swapRouter.exactOutputSingle(params);
    }

    /// @dev Swap tokens given the output amount using the saved path
    function _swapOutPath(
        bytes memory path,
        uint256 amountOut,
        uint256 amountMaximumIn
    ) private returns (uint256 amountIn) {
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams(
            path,
            msg.sender,
            block.timestamp,
            amountOut,
            amountMaximumIn
        );

        amountIn = _swapRouter.exactOutput(params);
    }

    /// @dev Returns the IUniswapV3Pool with given parameters, reverts if it does not exist
    function _poolExists(address token0, address token1, uint24 fee) private view returns (bool exists) {
        address poolAddr = _factory.getPool(token0, token1, fee);
        return poolAddr != address(0);
    }

    /// @dev Checks if the tokenIn and tokenOut in the swapPath matches the validTokenIn and validTokenOut specified
    function _checkPath(bytes memory path, address validTokenIn, address validTokenOut) private view {
        address tokenInFst;
        address tokenInMid;
        address tokenOut;
        uint24 fee;

        if (path.length < _MIN_PATH_LEN || path.length > _MAX_PATH_LEN) {
            revert InvalidPath();
        }

        // Decode the first pool in path
        (tokenInFst, tokenOut, fee) = path.decodeFirstPool();

        if (!_poolExists(tokenInFst, tokenOut, fee)) {
            revert InvalidPath();
        }

        while (path.hasMultiplePools()) {
            // Remove the first pool from path
            path = path.skipToken();
            // Check the next pool and update tokenOut
            address tokenOutPrev = tokenOut;
            (tokenInMid, tokenOut, fee) = path.decodeFirstPool();

            if (tokenOutPrev != tokenInMid) {
                revert InvalidPath();
            }

            if (!_poolExists(tokenInMid, tokenOut, fee)) {
                revert InvalidPath();
            }
        }

        if (tokenInFst != validTokenIn || tokenOut != validTokenOut) {
            revert InvalidPath();
        }
    }

    /// @dev Encodes the pair of token addresses into a unique bytes32 key
    function _encodePair(address tokenIn, address tokenOut) private pure returns (bytes32 key) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    /// @dev Reverses the given path (see multi hop swap-out)
    function _reversePath(bytes memory path) private pure returns (bytes memory) {
        address tokenA;
        address tokenB;
        uint24 fee;

        uint256 numPoolsPath = path.numPools();
        bytes[] memory singlePaths = new bytes[](numPoolsPath);

        // path := <token_0, fee_01, token_1, fee_12, token_2, ...>
        for (uint256 i = 0; i < numPoolsPath; i++) {
            (tokenA, tokenB, fee) = path.decodeFirstPool();
            singlePaths[i] = abi.encodePacked(tokenB, fee, tokenA);
            path = path.skipToken();
        }

        bytes memory reversedPath;
        bytes memory fullyReversedPath;
        // Get last element and create the first reversedPath
        (tokenA, tokenB, fee) = singlePaths[numPoolsPath - 1].decodeFirstPool();
        reversedPath = bytes.concat(bytes20(tokenA), bytes3(fee), bytes20(tokenB));
        fullyReversedPath = bytes.concat(fullyReversedPath, reversedPath);

        for (uint256 i = numPoolsPath - 1; i > 0; i--) {
            (, tokenB, fee) = singlePaths[i - 1].decodeFirstPool();
            // TokenA is just inserted as tokenB in the last sub path
            reversedPath = bytes.concat(bytes3(fee), bytes20(tokenB));
            fullyReversedPath = bytes.concat(fullyReversedPath, reversedPath);
        }

        return fullyReversedPath;
    }

    /// @dev Reverts if the given address is not set.
    function _zeroAddressCheck(address token) private pure {
        if (token == address(0)) {
            revert AddressZero();
        }
    }
}
