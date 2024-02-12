// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IExchange} from "@project/interfaces/IExchange.sol";
import {ISwapAdapter} from "@project/interfaces/ISwapAdapter.sol";
import {ChainlinkPriceOracle} from "@project/providers/chainlink/ChainlinkPriceOracle.sol";
import {SwapAdapterRouter} from "@project/providers/SwapAdapterRouter.sol";
import {UniswapAdapter} from "@project/providers/uniswap/UniswapAdapter.sol";
import {AddressProvider} from "@project/AddressProvider.sol";

/**
    @title SwapIntegrationTest
    @notice Test swap happens on uniswap adapter through router at correct price
 */
contract SwapIntegrationTest is Test {
    ChainlinkPriceOracle _priceOracle;
    SwapAdapterRouter _swapRouter;
    address _admin = address(0x01);

    // Tokens:
    address constant _USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant _WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address constant _WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Chainlink price feed aggregators:
    address constant _USDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address constant _WBTC_USD = 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57;
    address constant _ETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    // UniswapV3 contracts
    address constant _UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant _UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant _WETH_HOLDER = 0x940a7ed683A60220dE573AB702Ec8F789ef0A402;
    address constant _WBTC_HOLDER = 0x3B7424D5CC87dc2B670F4c99540f7380de3D5880;

    // ETH-USDC price in the selected block
    uint256 constant _CURR_WETH_USDC_PRICE = 1737.907785826880504425e18;
    uint256 constant _CURR_WBTC_USDC_PRICE = 25998.945155864298272056e18;

    constructor() {
        uint256 forkId = vm.createFork(vm.rpcUrl("arbitrum_mainnet"), 100768497);
        vm.selectFork(forkId);

        vm.startPrank(_admin);

        _priceOracle = new ChainlinkPriceOracle();
        _priceOracle.grantRole(_priceOracle.ROLE_ADMIN(), _admin);
        _priceOracle.setPriceFeed(_USDC, _USDC_USD);
        _priceOracle.setPriceFeed(_WETH, _ETH_USD);
        _priceOracle.setPriceFeed(_WBTC, _WBTC_USD);

        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), _admin);
        ap.setPriceOracle(address(_priceOracle));

        _swapRouter = new SwapAdapterRouter(address(ap), 0);
        _swapRouter.grantRole(_swapRouter.ROLE_ADMIN(), _admin);
        vm.stopPrank();
        ISwapAdapter uniswap = _uniSetup();
        vm.startPrank(_admin);
        _swapRouter.setAdapter(_WETH, _USDC, address(uniswap));
        _swapRouter.setAdapter(_WBTC, _USDC, address(uniswap));
        _swapRouter.setSlippage(_WETH, _USDC, 0.01e18); // 1%
        _swapRouter.setSlippage(_WBTC, _USDC, 0.01e18); // 1%
        vm.stopPrank();
    }

    function testSwapInWethUsdc() public {
        uint256 amountIn = 1e18; // 1 WETH
        uint256 cleanAmountOut = _expectedOut(_WETH, _USDC, amountIn, _CURR_WETH_USDC_PRICE);

        uint256 usdcBalBefore = IERC20Metadata(_USDC).balanceOf(_WETH_HOLDER);

        vm.startPrank(_WETH_HOLDER);
        IERC20Metadata(_WETH).approve(address(_swapRouter), amountIn);
        uint256 amountOut = _swapRouter.swapIn(_WETH, _USDC, amountIn);
        vm.stopPrank();

        uint256 usdcBalAfter = IERC20Metadata(_USDC).balanceOf(_WETH_HOLDER);

        assertEq(usdcBalAfter - usdcBalBefore, amountOut);
        assertApproxEqAbs(cleanAmountOut, amountOut, cleanAmountOut / 100); // slippage 1%
    }

    function testSwapOutWethUsdc() public {
        uint256 amountOut = 1e6; // 1 USDC
        uint256 cleanAmountIn = _expectedIn(_WETH, _USDC, amountOut, _CURR_WETH_USDC_PRICE);

        uint256 usdcBalBefore = IERC20Metadata(_USDC).balanceOf(_WETH_HOLDER);

        vm.startPrank(_WETH_HOLDER);
        uint256 maxAmountIn = _swapRouter.getInputAmountMax(_WETH, _USDC, amountOut);
        IERC20Metadata(_WETH).approve(address(_swapRouter), maxAmountIn);
        uint256 amountIn = _swapRouter.swapOut(_WETH, _USDC, amountOut, maxAmountIn);
        vm.stopPrank();

        uint256 usdcBalAfter = IERC20Metadata(_USDC).balanceOf(_WETH_HOLDER);

        assertEq(usdcBalAfter - usdcBalBefore, amountOut);
        assertApproxEqAbs(cleanAmountIn, amountIn, cleanAmountIn / 100);
    }

    function testSwapInWbtcUsdc() public {
        uint256 amountIn = 1e8; // 1 WBTC
        uint256 cleanAmountOut = _expectedOut(_WBTC, _USDC, amountIn, _CURR_WBTC_USDC_PRICE);

        uint256 usdcBalBefore = IERC20Metadata(_USDC).balanceOf(_WBTC_HOLDER);

        vm.startPrank(_WBTC_HOLDER);
        IERC20Metadata(_WBTC).approve(address(_swapRouter), amountIn);
        uint256 amountOut = _swapRouter.swapIn(_WBTC, _USDC, amountIn);
        vm.stopPrank();

        uint256 usdcBalAfter = IERC20Metadata(_USDC).balanceOf(_WBTC_HOLDER);

        assertEq(usdcBalAfter - usdcBalBefore, amountOut);
        assertApproxEqAbs(cleanAmountOut, amountOut, cleanAmountOut / 100); // slippage 1%
    }

    function testSwapOutWbtcUsdc() public {
        uint256 amountOut = 1e6; // 1 USDC
        uint256 cleanAmountIn = _expectedIn(_WBTC, _USDC, amountOut, _CURR_WBTC_USDC_PRICE);

        uint256 usdcBalBefore = IERC20Metadata(_USDC).balanceOf(_WBTC_HOLDER);

        vm.startPrank(_WBTC_HOLDER);
        uint256 maxAmountIn = _swapRouter.getInputAmountMax(_WBTC, _USDC, amountOut);
        IERC20Metadata(_WBTC).approve(address(_swapRouter), maxAmountIn);
        uint256 amountIn = _swapRouter.swapOut(_WBTC, _USDC, amountOut, maxAmountIn);
        vm.stopPrank();

        uint256 usdcBalAfter = IERC20Metadata(_USDC).balanceOf(_WBTC_HOLDER);

        assertEq(usdcBalAfter - usdcBalBefore, amountOut);
        assertApproxEqAbs(cleanAmountIn, amountIn, cleanAmountIn / 100);
    }

    function _uniSetup() private returns (ISwapAdapter) {
        vm.startPrank(_admin);
        UniswapAdapter _uniswap = new UniswapAdapter(_UNIV3_ROUTER, _UNIV3_FACTORY, 0);
        _uniswap.grantRole(_uniswap.ROLE_ADMIN(), _admin);
        vm.stopPrank();

        // Set single pool path for <WETH, USDC> to WETH -> USDC [0.3%]
        bytes memory wethUsdcPath = abi.encodePacked(address(_WETH), uint24(3000), address(_USDC));
        vm.prank(_admin);
        _uniswap.setPath(wethUsdcPath, address(_WETH), address(_USDC));

        // Set multi-pool path for <WBTC, USDC> to WBTC -> WETH [0.05%]-> USDC [0.05%]
        bytes memory wbtcUsdcPath = abi.encodePacked(
            address(_WBTC),
            uint24(500),
            address(_WETH),
            uint24(500),
            address(_USDC)
        );
        vm.prank(_admin);
        _uniswap.setPath(wbtcUsdcPath, address(_WBTC), address(_USDC));

        return _uniswap;
    }

    function _expectedOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 inPrice
    ) private view returns (uint256 expectedAmountOut) {
        return
            (amountIn * inPrice * 10 ** IERC20Metadata(tokenOut).decimals()) /
            (1e18 * 10 ** IERC20Metadata(tokenIn).decimals());
    }

    function _expectedIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 inPrice
    ) private view returns (uint256 expectedAmountIn) {
        return
            (amountOut * 1e18 * 10 ** IERC20Metadata(tokenIn).decimals()) /
            (inPrice * 10 ** IERC20Metadata(tokenOut).decimals());
    }
}
