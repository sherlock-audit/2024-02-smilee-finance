// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {Factory} from "./utils/Factory.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {DVP} from "@project/DVP.sol";
import {DVPType} from "@project/lib/DVPType.sol";
import {Registry} from "@project/periphery/Registry.sol";
import {Vault} from "@project/Vault.sol";
import {IG} from "@project/IG.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {Epoch} from "@project/lib/EpochController.sol";

contract FactoryTest is Test {
    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));

    address tokenAdmin = address(0x1);

    TestnetToken baseToken;
    TestnetToken sideToken;
    uint256 epochFrequency;
    Registry registry;
    Factory factory;

    function setUp() public {
        vm.startPrank(tokenAdmin);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), tokenAdmin);
        vm.stopPrank();

        vm.startPrank(tokenAdmin);
        registry = new Registry();

        ap.setRegistry(address(registry));
        ap.setExchangeAdapter(address(0x5));

        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setAddressProvider(address(ap));
        baseToken = token;

        token = new TestnetToken("Testnet WETH", "stWETH");
        token.setAddressProvider(address(ap));
        sideToken = token;

        factory = new Factory(address(ap));
        registry.grantRole(registry.ROLE_ADMIN(), address(factory));

        vm.stopPrank();

        vm.warp(EpochFrequency.REF_TS);
    }

    function testFactoryUnauthorized() public {
        //vm.startPrank(address(0x100));
        vm.expectRevert("Ownable: caller is not the owner");
        factory.createIGMarket(address(baseToken), address(sideToken), EpochFrequency.DAILY);
    }

    function testFactoryTokenBaseTokenZero() public {
        vm.prank(tokenAdmin);
        vm.expectRevert(AddressZero);
        factory.createIGMarket(address(0x0), address(sideToken), EpochFrequency.DAILY);
    }

    function testFactoryTokenSideTokenZero() public {
        vm.prank(tokenAdmin);
        vm.expectRevert(AddressZero);
        factory.createIGMarket(address(baseToken), address(0x0), EpochFrequency.DAILY);
    }

    function testFactoryCreatedDVP() public {
        vm.startPrank(tokenAdmin);
        address dvp = factory.createIGMarket(address(baseToken), address(sideToken), EpochFrequency.DAILY);
        DVP igDVP = DVP(dvp);

        assertEq(igDVP.baseToken(), address(baseToken));
        assertEq(igDVP.sideToken(), address(sideToken));
        assertEq(igDVP.optionType(), DVPType.IG);
        Epoch memory epoch = igDVP.getEpoch();
        assertEq(epoch.frequency, EpochFrequency.DAILY);
    }

    function testFactoryCreatedVault() public {
        vm.startPrank(tokenAdmin);
        address dvp = factory.createIGMarket(address(baseToken), address(sideToken), EpochFrequency.DAILY);
        DVP igDVP = DVP(dvp);
        Vault vault = Vault(igDVP.vault());

        assertEq(vault.baseToken(), address(baseToken));
        assertEq(vault.sideToken(), address(sideToken));
        Epoch memory epoch = vault.getEpoch();
        assertEq(epoch.frequency, EpochFrequency.DAILY);
    }
}
