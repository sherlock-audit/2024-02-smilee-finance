// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {AmountsMath} from "../../src/lib/AmountsMath.sol";
import {SignedMath} from "../../src/lib/SignedMath.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {Utils} from "../utils/Utils.sol";
import {MockedRegistry} from "../mock/MockedRegistry.sol";

contract TestnetSwapAdapterTest is Test {
    using AmountsMath for uint256;

    bytes4 constant TokenNotSupported = bytes4(keccak256("TokenNotSupported()"));
    bytes4 constant PriceZero = bytes4(keccak256("PriceZero()"));

    uint8 constant BTC_DECIMALS = 8;
    uint8 constant ETH_DECIMALS = 18;
    uint8 constant USD_DECIMALS = 7;

    address admin = address(0x1);
    address alice = address(0x2);

    TestnetPriceOracle priceOracle;
    TestnetSwapAdapter dex;
    TestnetToken WETH;
    TestnetToken WBTC;
    TestnetToken USD;
    MockedRegistry registry;

    constructor() {
        vm.startPrank(admin);
        USD = new TestnetToken("Testnet USD", "USD");
        USD.setDecimals(USD_DECIMALS);
        WETH = new TestnetToken("Testnet WETH", "WETH");
        WETH.setDecimals(ETH_DECIMALS);
        WBTC = new TestnetToken("Testnet WBTC", "WBTC");
        WBTC.setDecimals(BTC_DECIMALS);

        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), admin);
        registry = new MockedRegistry();
        priceOracle = new TestnetPriceOracle(address(USD));
        dex = new TestnetSwapAdapter(address(priceOracle));

        ap.setRegistry(address(registry));
        ap.setExchangeAdapter(address(dex));

        USD.setAddressProvider(address(ap));
        WETH.setAddressProvider(address(ap));
        WBTC.setAddressProvider(address(ap));
        vm.stopPrank();
    }

    function setUp() public {
        vm.startPrank(admin);
        priceOracle.setTokenPrice(address(WETH), 2_000e18);
        priceOracle.setTokenPrice(address(WBTC), 20_000e18);
        vm.stopPrank();
    }

    function testCannotChangePriceOracle() public {
        vm.expectRevert("Ownable: caller is not the owner");
        dex.changePriceOracle(address(0x100));
    }

    function testChangePriceOracle() public {
        vm.startPrank(admin);
        TestnetPriceOracle newPriceOracle = new TestnetPriceOracle(address(USD));

        dex.changePriceOracle(address(newPriceOracle));
        // TBD: priceOracle is internal. Evaluate to create a getter.
        //assertEq(address(newPriceOracle), dex.priceOracle);
    }

    function testGetOutputAmountOfZero() public {
        uint256 amountToReceive = dex.getOutputAmount(address(WETH), address(WBTC), 0);
        assertEq(0, amountToReceive);
    }

    /**
        TBD: What happens when someone tries to swap the same token.
     */
    function testGetOutputAmountOfSameToken() public {
        uint256 amountToReceive = dex.getOutputAmount(address(WETH), address(WETH), 1 ether);
        assertEq(1 ether, amountToReceive);
    }

    function testGetOutputAmount() public {
        // NOTE: WETH is priced 2000 USD, WBTC is priced 20000 USD.
        uint256 input = AmountsMath.unwrapDecimals(1e18, ETH_DECIMALS);
        uint256 expectedOutput = AmountsMath.unwrapDecimals(0.1e18, BTC_DECIMALS);
        uint256 amountToReceive = dex.getOutputAmount(address(WETH), address(WBTC), input);
        assertEq(expectedOutput, amountToReceive);

        input = AmountsMath.unwrapDecimals(1e18, BTC_DECIMALS);
        expectedOutput = AmountsMath.unwrapDecimals(10e18, ETH_DECIMALS);
        amountToReceive = dex.getOutputAmount(address(WBTC), address(WETH), input);
        assertEq(expectedOutput, amountToReceive);
    }

    /**
        Input swap - alice inputs 10 WETH, gets 1 WBTC.
        Test if `getSwapAmount()` and the actual swap give the same result beside performing the swap.
     */
    function testSwapIn() public {
        TokenUtils.provideApprovedTokens(admin, address(WETH), alice, address(dex), 100 ether, vm);

        uint256 input = 10 ether; // WETH
        uint256 amountToReceive = dex.getOutputAmount(address(WETH), address(WBTC), input);

        vm.prank(alice);
        dex.swapIn(address(WETH), address(WBTC), input);

        assertEq(90 ether, WETH.balanceOf(alice));
        assertEq(amountToReceive, WBTC.balanceOf(alice));
    }

    function testGetInputAmountOfZero() public {
        uint256 amountToProvide = dex.getInputAmount(address(WETH), address(WBTC), 0);
        assertEq(0, amountToProvide);
    }

    /**
        TBD: What happens when someone tries to swap the same token.
     */
    function testGetInputAmountOfSameToken() public {
        uint256 amountToProvide = dex.getInputAmount(address(WETH), address(WETH), 1 ether);
        assertEq(1 ether, amountToProvide);
    }

    function testGetInputAmount() public {
        // NOTE: WETH is priced 2000 USD, WBTC is priced 20000 USD.
        uint256 input = AmountsMath.unwrapDecimals(1e18, BTC_DECIMALS);
        uint256 expectedOutput = AmountsMath.unwrapDecimals(10e18, ETH_DECIMALS);
        uint256 amountToProvide = dex.getInputAmount(address(WETH), address(WBTC), input);
        assertEq(expectedOutput, amountToProvide);

        input = AmountsMath.unwrapDecimals(1e18, ETH_DECIMALS);
        expectedOutput = AmountsMath.unwrapDecimals(0.1e18, BTC_DECIMALS);
        amountToProvide = dex.getInputAmount(address(WBTC), address(WETH), 1 ether);
        assertEq(expectedOutput, amountToProvide);
    }

    /**
        Output swap - alice wants 1 WBTC, inputs 10 WETH
     */
    function testSwapOut() public {
        TokenUtils.provideApprovedTokens(admin, address(WETH), alice, address(dex), 100 ether, vm);

        uint256 wanted = AmountsMath.unwrapDecimals(1e18, BTC_DECIMALS); // WBTC
        uint256 amountToGive = dex.getInputAmount(address(WETH), address(WBTC), wanted);
        assertEq(10 ether, amountToGive);

        vm.prank(alice);
        dex.swapOut(address(WETH), address(WBTC), wanted, amountToGive);

        assertEq(90 ether, WETH.balanceOf(alice));
        assertEq(wanted, WBTC.balanceOf(alice));
    }

    /**
        Test `swapIn()` for fuzzy values of WBTC / WETH price
     */
    function testFuzzyPriceSwapIn(uint256 price) public {
        bool success = _setWbtcWethPrice(price);
        if (!success) {
            return;
        }

        uint256 input = 1 ether; // WETH
        TokenUtils.provideApprovedTokens(admin, address(WETH), alice, address(dex), input, vm);

        if (price == 0) {
            vm.expectRevert(PriceZero);
            dex.getOutputAmount(address(WETH), address(WBTC), input);
            return;
        }

        uint256 wbtcForWethAmount = dex.getOutputAmount(address(WETH), address(WBTC), input);
        uint256 expextedWbtcForWethAmount = AmountsMath.unwrapDecimals(input.wdiv(price), BTC_DECIMALS);
        assertEq(expextedWbtcForWethAmount, wbtcForWethAmount);

        vm.prank(alice);
        dex.swapIn(address(WETH), address(WBTC), input);
        assertEq(0, WETH.balanceOf(alice));
        assertEq(expextedWbtcForWethAmount, WBTC.balanceOf(alice));
    }

    /**
        Test `swapOut()` for fuzzy values of WBTC / WETH price
     */
    function testFuzzyPriceSwapOut(uint256 price) public {
        bool success = _setWbtcWethPrice(price);
        if (!success) {
            return;
        }

        vm.assume(price < 1e18 * 1e18);
        uint256 output = AmountsMath.unwrapDecimals(1e18, BTC_DECIMALS);

        if (price == 0) {
            vm.expectRevert(PriceZero);
            dex.getInputAmount(address(WETH), address(WBTC), output);
            return;
        }

        uint256 wethForWbtcAmount = dex.getInputAmount(address(WETH), address(WBTC), output);

        uint256 expextedWethForWbtcAmount = AmountsMath.wrapDecimals(output, BTC_DECIMALS).wmul(price);
        assertEq(expextedWethForWbtcAmount, wethForWbtcAmount);

        TokenUtils.provideApprovedTokens(admin, address(WETH), alice, address(dex), wethForWbtcAmount, vm);

        vm.prank(alice);
        dex.swapOut(address(WETH), address(WBTC), output, wethForWbtcAmount);
        assertEq(0, WETH.balanceOf(alice));
        assertEq(output, WBTC.balanceOf(alice));
    }

    function _setWbtcWethPrice(uint256 price) private returns (bool success) {
        success = false;

        uint256 wethPrice = priceOracle.getPrice(address(WETH), address(USD));
        if (price > type(uint256).max / wethPrice) {
            return false;
        }
        uint256 priceToSet = price.wmul(wethPrice);
        uint256 priceLimit = type(uint256).max / 1e18;
        vm.startPrank(admin);
        if (priceToSet > priceLimit) {
            vm.expectRevert();
        }
        priceOracle.setTokenPrice(address(WBTC), priceToSet);
        vm.stopPrank();
        success = true;
    }

    function testRandom(int256 min, int256 max) public view {
        vm.assume(min < max);
        vm.assume(SignedMath.abs(min) < type(uint128).max);
        vm.assume(SignedMath.abs(max) < type(uint128).max);

        int256 random = dex.random(min, max);
        assert(random <= max);
        assert(random >= min);
    }

    function testExactSlip() public {
        vm.prank(admin);
        dex.setSlippage(0.03e18, 0, 0); // -3%
        uint256 slippedAmount = dex.slipped(100, false);
        assertEq(slippedAmount, 97);

        vm.prank(admin);
        dex.setSlippage(-0.03e18, 0, 0); // -3%
        slippedAmount = dex.slipped(100, true);
        assertEq(slippedAmount, 97);

        vm.prank(admin);
        dex.setSlippage(0.03e18, 0, 0); // +3%
        slippedAmount = dex.slipped(100, true);
        assertEq(slippedAmount, 103);

        vm.prank(admin);
        dex.setSlippage(-0.03e18, 0, 0); // +3%
        slippedAmount = dex.slipped(100, false);
        assertEq(slippedAmount, 103);
    }

    function testExactSlipFuz() public /* int256 slippage, uint256 amount */ {
        int256 slippage = -1;
        uint256 amount = 1;
        // vm.assume(SignedMath.abs(slippage) < 1e18);
        // vm.assume(amount < type(uint128).max);
        vm.prank(admin);
        dex.setSlippage(slippage, 0, 0);
        uint256 slippedAmount = dex.slipped(amount, true);
        int256 expectedSlip = (slippage * int256(amount)) / 1e18;
        assertApproxEqAbs(uint256(int(amount) + expectedSlip), slippedAmount, 1);
    }

    function testRandomSlip(uint256 delay) public {
        vm.prank(admin);
        vm.assume(delay < type(uint128).max);
        vm.warp(block.timestamp + delay);

        dex.setSlippage(0, -0.03e18, 0); // -3%
        uint256 slippedAmount = dex.slipped(100, true);
        assert(slippedAmount >= 97);
        assert(slippedAmount <= 100);

        vm.prank(admin);
        dex.setSlippage(0, 0, 0.03e18); // +3%
        slippedAmount = dex.slipped(100, true);
        assert(slippedAmount <= 103);
        assert(slippedAmount >= 100);

        vm.prank(admin);
        dex.setSlippage(0, 0.025e18, 0.03e18); // [2.5%, 3%]
        slippedAmount = dex.slipped(1000, true);
        assert(slippedAmount <= 1030);
        assert(slippedAmount >= 1025);
    }

    function testRandomSlipFuz() public /* int256 minSlippage, int256 maxSlippage, uint256 amount */ {
        int256 minSlippage = -2;
        int256 maxSlippage = 0;
        uint256 amount = 1;
        // vm.assume(SignedMath.abs(minSlippage) < 1e18);
        // vm.assume(SignedMath.abs(maxSlippage) < 1e18);
        // vm.assume(minSlippage < maxSlippage);
        // vm.assume(amount < type(uint128).max);
        vm.prank(admin);

        dex.setSlippage(0, minSlippage, maxSlippage);
        int256 minExpectedSlipped = int256(amount) * (1e18 + minSlippage) / 1e18;
        int256 maxExpectedSlipped = int256(amount) * (1e18 + maxSlippage) / 1e18;
        uint256 slippedAmount = dex.slipped(amount, true);

        assert(minExpectedSlipped >= 0);
        assert(maxExpectedSlipped >= 0);
        assertLe(slippedAmount, uint256(maxExpectedSlipped));
        assertGe(slippedAmount, uint256(minExpectedSlipped));
    }
}
