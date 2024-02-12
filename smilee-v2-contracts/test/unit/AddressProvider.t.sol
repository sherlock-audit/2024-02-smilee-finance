// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {Utils} from "../utils/Utils.sol";

contract AddressProviderTest is Test {
    address tokenAdmin = address(0x1);

    AddressProvider addressProvider;

    function setUp() public {
        vm.startPrank(tokenAdmin);
        addressProvider = new AddressProvider(1 days);
        addressProvider.grantRole(addressProvider.ROLE_ADMIN(), tokenAdmin);
        vm.stopPrank();
    }

    function testAddressProviderUnauthorized() public {
        //vm.startPrank(address(0x100));
        vm.expectRevert();
        addressProvider.setExchangeAdapter(address(0x100));
    }

    function testAddressProviderTimeLocked() public {
        vm.startPrank(tokenAdmin);

        addressProvider.setExchangeAdapter(address(0x100));
        assertEq(address(0x100), addressProvider.exchangeAdapter());

        addressProvider.setExchangeAdapter(address(0x999));
        vm.stopPrank();

        assertEq(address(0x100), addressProvider.exchangeAdapter());
        Utils.skipDay(true, vm);
        assertEq(address(0x999), addressProvider.exchangeAdapter());
    }

    function testAddressProviderSetExchangeAdapter() public {
        vm.prank(tokenAdmin);
        addressProvider.setExchangeAdapter(address(0x100));

        assertEq(address(0x100), addressProvider.exchangeAdapter());
    }

    function testAddressProviderSetPriceOracle() public {
        vm.prank(tokenAdmin);
        addressProvider.setPriceOracle(address(0x101));

        assertEq(address(0x101), addressProvider.priceOracle());
    }

    function testAddressProviderSetMarketOracle() public {
        vm.prank(tokenAdmin);
        addressProvider.setMarketOracle(address(0x102));

        assertEq(address(0x102), addressProvider.marketOracle());
    }

    function testAddressProviderSetRegistry() public {
        vm.prank(tokenAdmin);
        addressProvider.setRegistry(address(0x103));

        assertEq(address(0x103), addressProvider.registry());
    }
}
