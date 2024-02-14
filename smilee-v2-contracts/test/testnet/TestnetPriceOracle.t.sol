// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import "forge-std/console.sol";

contract TestnetPriceOracleTest is Test {
    bytes4 constant TokenNotSupported = bytes4(keccak256("TokenNotSupported()"));
    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant PriceZero = bytes4(keccak256("PriceZero()"));
    bytes4 constant PriceTooHigh = bytes4(keccak256("PriceTooHigh()"));

    address admin = address(0x1);
    address referenceToken = address(0x10000);
    TestnetPriceOracle priceOracle;

    constructor() {
        vm.prank(admin);
        priceOracle = new TestnetPriceOracle(referenceToken);
    }

    function testUnauthorized() public {
        vm.expectRevert("Ownable: caller is not the owner");
        priceOracle.setTokenPrice(address(0x100), 10);
    }

    function testZeroSetFail() public {
        vm.prank(admin);
        vm.expectRevert(AddressZero);
        priceOracle.setTokenPrice(address(0), 10);
    }

    function testSetTokenPrice() public {
        address aToken = address(0x10001);
        vm.prank(admin);
        priceOracle.setTokenPrice(aToken, 10e18);
        assertEq(10e18, priceOracle.getTokenPrice(aToken));
    }

    function testGetTokenPriceReferenceToken() public {
        assertEq(1e18, priceOracle.getTokenPrice(referenceToken));
    }

    function testGetTokenPriceAddressZero() public {
        vm.expectRevert(AddressZero);
        priceOracle.getTokenPrice(address(0));
    }

    function testGetTokenPriceMissingToken() public {
        address aToken = address(0x10001); // not listed token

        vm.expectRevert(TokenNotSupported);
        priceOracle.getTokenPrice(aToken);
    }

    /**
     * An user tries to get the price of a pair coitains the 0 address. A TokenNotSupported error should be reverted.
     */
    function testGetPriceZeroAddressFail() public {
        address aToken = address(0x10001);

        vm.prank(admin);
        priceOracle.setTokenPrice(aToken, 10e18);

        vm.expectRevert(AddressZero);
        priceOracle.getPrice(address(0), aToken);

        vm.expectRevert(AddressZero);
        priceOracle.getPrice(aToken, address(0));
    }

    function testGetPrice() public {
        address t0 = address(0x10001);
        address t1 = address(0x10002);

        vm.startPrank(admin);
        priceOracle.setTokenPrice(t0, 10e18);
        priceOracle.setTokenPrice(t1, 8e18);
        vm.stopPrank();

        uint256 price = priceOracle.getPrice(t0, t1);
        assertEq(125e16, price); // 1.25
    }

    /**
        Test setting and getting fuzzy value price for a t1 w.r.t. t0
     */
    function testFuzzySetPrice(uint256 price) public {
        address t0 = address(0x10001);
        address t1 = address(0x10002);

        if (price > type(uint256).max / 1e18) {
            vm.expectRevert(PriceTooHigh);
            _setPrice(t0, t1, price);
            return;
        }

        _setPrice(t0, t1, price);

        uint256 oraclePrice = priceOracle.getPrice(t1, t0);
        assertEq(price, oraclePrice);
    }

    function _setPrice(address t0, address t1, uint256 price) private {
        vm.startPrank(admin);
        priceOracle.setTokenPrice(t1, price);
        priceOracle.setTokenPrice(t0, 1e18); // unitary price for t0
        vm.stopPrank();
    }
}
