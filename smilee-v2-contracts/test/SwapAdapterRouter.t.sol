// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {IExchange} from "@project/interfaces/IExchange.sol";
import {IPriceOracle} from "@project/interfaces/IPriceOracle.sol";
import {AmountsMath} from "@project/lib/AmountsMath.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {SwapAdapterRouter} from "@project/providers/SwapAdapterRouter.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {Utils} from "./utils/Utils.sol";

contract SwapProviderRouterTest is Test {
    bytes4 constant _ADDRESS_ZERO = bytes4(keccak256("AddressZero()"));
    bytes4 constant _SLIPPAGE = bytes4(keccak256("Slippage()"));
    bytes4 constant _SWAP_ZERO = bytes4(keccak256("SwapZero()"));
    bytes4 constant _INSUFF_INPUT = bytes4(keccak256("InsufficientInput()"));

    address _admin = address(0x1);
    address _alice = address(0x2);

    TestnetToken _token0;
    TestnetToken _token1;
    AddressProvider _ap;
    IPriceOracle _oracle;
    SwapAdapterRouter _swapRouter;
    IPriceOracle _swapOracle;
    IExchange _swap;

    function setUp() public {
        vm.startPrank(_admin);

        _ap = new AddressProvider(0);
        _ap.grantRole(_ap.ROLE_ADMIN(), _admin);

        _oracle = new TestnetPriceOracle(address(0x123));
        _swapOracle = new TestnetPriceOracle(address(0x123));
        _swap = new TestnetSwapAdapter(address(_swapOracle));
        _swapRouter = new SwapAdapterRouter(address(_ap), 0);
        _swapRouter.grantRole(_swapRouter.ROLE_ADMIN(), _admin);

        MockedRegistry r = new MockedRegistry();
        r.grantRole(r.ROLE_ADMIN(), _admin);

        _ap.setPriceOracle(address(_oracle));
        _ap.setExchangeAdapter(address(_swap));
        _ap.setRegistry(address(r));
        _token0 = new TestnetToken("USDC", "");
        // _token0.setDecimals(12);
        _token1 = new TestnetToken("ETH", "");
        // _token1.setDecimals(6);
        _token0.setAddressProvider(address(_ap));
        _token1.setAddressProvider(address(_ap));
        vm.stopPrank();
    }

    function testConstructor() public {
        vm.expectRevert();
        _swapRouter.setAdapter(address(_token0), address(_token1), address(0x100));

        vm.expectRevert();
        _swapRouter.setSlippage(address(_token0), address(_token1), 500);
    }

    function testSetters() public {
        vm.startPrank(_admin);

        _swapRouter.setAdapter(address(_token0), address(_token1), address(0x101));
        assertEq(address(0x101), _swapRouter.getAdapter(address(_token0), address(_token1)));

        _swapRouter.setSlippage(address(_token0), address(_token1), 0.05e18);
        assertEq(0.05e18, _swapRouter.getSlippage(address(_token0), address(_token1)));

        vm.stopPrank();
    }

    /// @dev Fail when giving too little input
    function testSwapInFailDown() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 1.5e18;
        uint256 maxSlippage = 0.1e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, true);

        vm.startPrank(_alice);
        _token0.approve(address(_swapRouter), amount);
        vm.expectRevert(_SLIPPAGE);
        _swapRouter.swapIn(address(_token0), address(_token1), amount);
        vm.stopPrank();
    }

    /// @dev Fail when giving too much output
    function testSwapInFailUp() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 0.5e18;
        uint256 maxSlippage = 0.1e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, true);

        vm.startPrank(_alice);
        _token0.approve(address(_swapRouter), amount);
        vm.expectRevert(_SLIPPAGE);
        _swapRouter.swapIn(address(_token0), address(_token1), amount);
        vm.stopPrank();
    }

    function testSwapInOk() public {
        uint256 amount = 1_000_000_000_000e6;

        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 1.1e18;
        uint256 maxSlippage = 0.1e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, true);

        vm.startPrank(_alice);
        _token0.approve(address(_swapRouter), amount);
        _swapRouter.swapIn(address(_token0), address(_token1), amount);
        assertEq(0, _token0.balanceOf(_alice));

        amount = AmountsMath.wrapDecimals(amount, _token0.decimals());
        uint256 token1Amount = AmountsMath.unwrapDecimals(AmountsMath.wdiv(amount, swapPriceRef), _token1.decimals());
        assertApproxEqAbs(token1Amount, _token1.balanceOf(_alice), amount / 1e18);
        vm.stopPrank();
    }

    /// @dev Fail when requiring too much input
    function testSwapOutFailUp() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 1.5e18;
        uint256 maxSlippage = 0.1e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, false);

        vm.startPrank(_alice);
        uint256 t0IniBal = _token0.balanceOf(_alice);
        _token0.approve(address(_swapRouter), t0IniBal);
        vm.expectRevert(_INSUFF_INPUT);
        _swapRouter.swapOut(address(_token0), address(_token1), amount, t0IniBal);
        vm.stopPrank();
    }

    /// @dev Fail when requiring too little input
    function testSwapOutFailDown() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 0.5e18;
        uint256 maxSlippage = 0.1e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, false);

        vm.startPrank(_alice);
        uint256 t0IniBal = _token0.balanceOf(_alice);
        _token0.approve(address(_swapRouter), t0IniBal);
        vm.expectRevert(_SLIPPAGE);
        _swapRouter.swapOut(address(_token0), address(_token1), amount, t0IniBal);
        vm.stopPrank();
    }

    function testSwapOutOk() public {
        uint256 amount = 1e18;
        uint256 realPriceRef = 1e18;
        uint256 swapPriceRef = 1.1e18;
        uint256 maxSlippage = 0.1e18;
        _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, false);

        vm.startPrank(_alice);
        uint256 t0IniBal = _token0.balanceOf(_alice);

        amount = AmountsMath.wrapDecimals(amount, _token1.decimals());
        uint256 shouldSpend = AmountsMath.unwrapDecimals(AmountsMath.wmul(amount, swapPriceRef), _token0.decimals());

        _token0.approve(address(_swapRouter), t0IniBal);

        amount = AmountsMath.unwrapDecimals(amount, _token1.decimals());
        uint256 spent = _swapRouter.swapOut(address(_token0), address(_token1), amount, t0IniBal);

        assertApproxEqAbs(shouldSpend, spent, 1e3);
        assertEq(t0IniBal - spent, _token0.balanceOf(_alice));
        assertEq(amount, _token1.balanceOf(_alice));
        vm.stopPrank();
    }

    function testSwapInFuzzy(uint256 amountIn, uint256 realPriceRef, uint256 swapPriceRef, uint256 maxSlippage) public {
        amountIn = bound(amountIn, 1e9, type(uint128).max); // avoid price to be too big
        realPriceRef = bound(realPriceRef, 1e9, type(uint128).max); // avoid price to be too big
        swapPriceRef = bound(swapPriceRef, 1e9, type(uint128).max); // avoid price to be too big
        vm.assume(realPriceRef < swapPriceRef);
        maxSlippage = bound(maxSlippage, 0.005e18, 0.1e18); // was 0.1% - 50% - significant values

        _adminSetup(amountIn, realPriceRef, swapPriceRef, maxSlippage, true);
        uint256 realPrice = _oracle.getPrice(address(_token0), address(_token1));
        uint256 swapPrice = _swapOracle.getPrice(address(_token0), address(_token1));

        vm.startPrank(_alice);
        _token0.approve(address(_swapRouter), amountIn);

        // check if expected output is 0
        uint256 expectedOutput = (((amountIn * _swapOracle.getPrice(address(_token0), address(_token1))) / 1e18) *
            10 ** _token1.decimals()) / 10 ** _token0.decimals();

        if (expectedOutput == 0) {
            vm.expectRevert(_SWAP_ZERO);
            _swapRouter.swapIn(address(_token0), address(_token1), amountIn);
        } else if (_priceRangeOk(realPrice, swapPrice, maxSlippage)) {
            _swapRouter.swapIn(address(_token0), address(_token1), amountIn);
            assertEq(0, _token0.balanceOf(_alice));
            assertApproxEqAbs(
                (((amountIn * 1e18) / swapPriceRef) * 10 ** _token1.decimals()) / 10 ** _token0.decimals(),
                _token1.balanceOf(_alice),
                amountIn / 1e9
            );
        } else {
            vm.expectRevert(_SLIPPAGE);
            _swapRouter.swapIn(address(_token0), address(_token1), amountIn);
        }
        vm.stopPrank();
    }

    // function testSwapOutFuzzy(uint256 amount, uint256 realPriceRef, uint256 swapPriceRef, uint256 maxSlippage) public {
    //     amount = bound(amount, 1e9, type(uint128).max); // avoid price to be too big
    //     realPriceRef = bound(realPriceRef, 1e9, type(uint128).max); // avoid price to be too big
    //     swapPriceRef = bound(swapPriceRef, 1e9, type(uint128).max); // avoid price to be too big
    //     vm.assume(realPriceRef < swapPriceRef);
    //     maxSlippage = bound(maxSlippage, 0.001e18, 0.5e18); // 0.1 - 50% - significant values

    //     _adminSetup(amount, realPriceRef, swapPriceRef, maxSlippage, false);
    //     uint256 realPrice = _oracle.getPrice(address(_token0), address(_token1));
    //     uint256 swapPrice = _swapOracle.getPrice(address(_token0), address(_token1));

    //     vm.startPrank(_alice);
    //     uint256 t0IniBal = _token0.balanceOf(_alice);
    //     uint256 shouldSpend = (amount * swapPriceRef) / 10 ** _token1.decimals();
    //     _token0.approve(address(_swapRouter), t0IniBal);

    //     if (_priceRangeOk(realPrice, swapPrice, maxSlippage)) {
    //         uint256 spent = _swapRouter.swapOut(address(_token0), address(_token1), amount);
    //         assertApproxEqAbs(shouldSpend, spent, shouldSpend / 1e18);
    //         assertEq(t0IniBal - spent, _token0.balanceOf(_alice));
    //         assertEq(amount, _token1.balanceOf(_alice));
    //     } else {
    //         if (_priceRangeOkLow(realPrice, swapPrice, maxSlippage)) {
    //             vm.expectRevert("ERC20: insufficient allowance");
    //         } else {
    //             vm.expectRevert(_SLIPPAGE);
    //         }
    //         _swapRouter.swapOut(address(_token0), address(_token1), amount);
    //     }
    //     vm.stopPrank();
    // }

    function _adminSetup(
        uint256 swapAmount,
        uint256 realPriceRef,
        uint256 swapPriceRef,
        uint256 maxSlippage,
        bool isIn
    ) private {
        vm.startPrank(_admin);
        TestnetPriceOracle(address(_oracle)).setTokenPrice(address(_token0), 1e18);
        TestnetPriceOracle(address(_oracle)).setTokenPrice(address(_token1), realPriceRef);
        TestnetPriceOracle(address(_swapOracle)).setTokenPrice(address(_token0), 1e18);
        TestnetPriceOracle(address(_swapOracle)).setTokenPrice(address(_token1), swapPriceRef);
        _swapRouter.setAdapter(address(_token0), address(_token1), address(_swap));
        _swapRouter.setAdapter(address(_token1), address(_token0), address(_swap));
        _swapRouter.setSlippage(address(_token0), address(_token1), maxSlippage);
        _swapRouter.setSlippage(address(_token1), address(_token0), maxSlippage);
        _token0.setTransferRestriction(false);
        _token1.setTransferRestriction(false);

        if (isIn) {
            _token0.mint(_alice, swapAmount);
        } else {
            uint256 amountInMax = _swapRouter.getInputAmountMax(address(_token0), address(_token1), swapAmount);
            _token0.mint(_alice, amountInMax);
        }
        vm.stopPrank();
    }

    /// @dev Tells if the swap price within a range from the real one +/- slippage
    function _priceRangeOk(uint256 realPrice, uint256 swapPrice, uint256 maxSlippage) private pure returns (bool) {
        return
            _priceRangeOkHigh(realPrice, swapPrice, maxSlippage) && _priceRangeOkLow(realPrice, swapPrice, maxSlippage);
    }

    function _priceRangeOkHigh(uint256 realPrice, uint256 swapPrice, uint256 maxSlippage) private pure returns (bool) {
        return swapPrice * 1e18 <= realPrice * (1e18 + maxSlippage);
    }

    function _priceRangeOkLow(uint256 realPrice, uint256 swapPrice, uint256 maxSlippage) private pure returns (bool) {
        return swapPrice * 1e18 >= realPrice * (1e18 - maxSlippage);
    }
}
