// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {Epoch, EpochController} from "@project/lib/EpochController.sol";

contract RegistryTest is Test {
    using EpochController for Epoch;

    bytes4 constant MissingAddress = bytes4(keccak256("MissingAddress()"));
    MockedRegistry registry;
    MockedIG dvp;
    address admin = address(0x21);
    AddressProvider ap;

    constructor() {
        vm.warp(EpochFrequency.REF_TS);

        vm.startPrank(admin);

        ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), admin);

        registry = new MockedRegistry();
        registry.grantRole(registry.ROLE_ADMIN(), admin);
        ap.setRegistry(address(registry));

        vm.stopPrank();

        MockedVault vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        vm.startPrank(admin);
        dvp = new MockedIG(address(vault), address(ap));

        dvp.grantRole(dvp.ROLE_ADMIN(), admin);
        dvp.grantRole(dvp.ROLE_EPOCH_ROLLER(), admin);
        vm.stopPrank();
    }

    function testNotRegisteredAddress() public {
        address addrToCheck = address(0x150);

        assertEq(false, registry.isRegistered(addrToCheck));
        assertEq(false, registry.isRegisteredVault(addrToCheck));
    }

    function testRegisterDVP() public {
        address addrToRegister = address(dvp);

        bool isAddressRegistered = registry.isRegistered(addrToRegister);
        assertEq(false, isAddressRegistered);

        vm.prank(admin);
        registry.register(addrToRegister);

        assertEq(true, registry.isRegistered(addrToRegister));
        assertEq(true, registry.isRegisteredVault(dvp.vault()));
    }

    function testUnregisterDVPFail() public {
        address addrToUnregister = address(0x150);
        vm.expectRevert(MissingAddress);
        vm.prank(admin);
        registry.unregister(addrToUnregister);
    }

    function testUnregisterAddress() public {
        address addrToUnregister = address(dvp);

        vm.prank(admin);
        registry.register(addrToUnregister);
        assertEq(true, registry.isRegistered(addrToUnregister));
        assertEq(true, registry.isRegisteredVault(dvp.vault()));

        vm.prank(admin);
        registry.unregister(addrToUnregister);

        assertEq(false, registry.isRegistered(addrToUnregister));
        assertEq(false, registry.isRegisteredVault(dvp.vault()));
    }

    function testSideTokenIndexing() public {
        address dvpAddr = address(dvp);
        vm.prank(admin);
        registry.register(dvpAddr);

        address tokenAddr = dvp.sideToken();
        address[] memory tokens = registry.getSideTokens();
        address[] memory dvps = registry.getDvpsBySideToken(tokenAddr);

        assertEq(1, tokens.length);
        assertEq(tokenAddr, tokens[0]);

        assertEq(1, dvps.length);
        assertEq(dvpAddr, dvps[0]);

        vm.prank(admin);
        registry.unregister(dvpAddr);

        tokens = registry.getSideTokens();
        dvps = registry.getDvpsBySideToken(tokenAddr);

        assertEq(0, tokens.length);
        assertEq(0, dvps.length);
    }

    function testSideTokenIndexingDup() public {
        address dvpAddr = address(dvp);
        vm.prank(admin);
        registry.register(dvpAddr);

        vm.prank(admin);
        registry.register(dvpAddr);

        address tokenAddr = dvp.sideToken();
        address[] memory tokens = registry.getSideTokens();
        address[] memory dvps = registry.getDvpsBySideToken(tokenAddr);

        assertEq(1, tokens.length);
        assertEq(tokenAddr, tokens[0]);

        assertEq(1, dvps.length);
        assertEq(dvpAddr, dvps[0]);
    }

    function testMultiSideTokenIndexing() public {
        MockedVault vault2 = MockedVault(VaultUtils.createVaultSideTokenSym(dvp.baseToken(), "JOE", EpochFrequency.DAILY, ap, admin, vm));
        MockedIG dvp2 = new MockedIG(address(vault2), address(ap));

        vm.prank(admin);
        registry.register(address(dvp));

        vm.prank(admin);
        registry.register(address(dvp2));

        address[] memory tokens = registry.getSideTokens();
        assertEq(2, tokens.length);
        assertEq(dvp.sideToken(), tokens[0]);
        assertEq(dvp2.sideToken(), tokens[1]);

        address[] memory dvps = registry.getDvpsBySideToken(dvp.sideToken());
        assertEq(1, dvps.length);
        assertEq(address(dvp), dvps[0]);

        dvps = registry.getDvpsBySideToken(dvp2.sideToken());
        assertEq(1, dvps.length);
        assertEq(address(dvp2), dvps[0]);

        vm.prank(admin);
        registry.unregister(address(dvp));

        tokens = registry.getSideTokens();
        assertEq(1, tokens.length);
        assertEq(dvp2.sideToken(), tokens[0]);

        dvps = registry.getDvpsBySideToken(dvp.sideToken());
        assertEq(0, dvps.length);

        dvps = registry.getDvpsBySideToken(dvp2.sideToken());
        assertEq(1, dvps.length);
        assertEq(address(dvp2), dvps[0]);
    }

    function testDVPToRoll() public {
        vm.startPrank(admin);
        MockedVault vault = MockedVault(dvp.vault());
        vault.grantRole(vault.ROLE_ADMIN(), admin);
        vault.setAllowedDVP(address(dvp));
        vm.stopPrank();


        MockedVault vault2 = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        vm.startPrank(admin);
        vault2.grantRole(vault2.ROLE_ADMIN(), admin);

        MockedIG dvp2 = new MockedIG(address(vault2), address(ap));
        dvp2.grantRole(dvp2.ROLE_ADMIN(), admin);
        dvp2.grantRole(dvp2.ROLE_EPOCH_ROLLER(), admin);
        vm.stopPrank();

        MarketOracle mo = MarketOracle(ap.marketOracle());


        TestnetPriceOracle po = TestnetPriceOracle(ap.priceOracle());

        vm.startPrank(admin);

        mo.setDelay(dvp.baseToken(), dvp.sideToken(), dvp.getEpoch().frequency, 0, true);
        mo.setDelay(dvp2.baseToken(), dvp2.sideToken(), dvp2.getEpoch().frequency, 0, true);

        registry.register(address(dvp));
        registry.register(address(dvp2));
        vault2.setAllowedDVP(address(dvp2));
        po.setTokenPrice(vault2.baseToken(), 1e18);
        vm.stopPrank();

        Utils.skipDay(true, vm);
        vm.prank(admin);
        dvp2.rollEpoch();

        Epoch memory dvpEpoch = dvp.getEpoch();
        uint256 timeToNextEpochDvp = dvpEpoch.timeToNextEpoch();
        assertEq(0, timeToNextEpochDvp);

        Epoch memory dvp2Epoch = dvp2.getEpoch();
        uint256 timeToNextEpochDvp2 = dvp2Epoch.timeToNextEpoch();
        assertApproxEqAbs(86400, timeToNextEpochDvp2, 10);

        (address[] memory dvps, uint256 dvpsToRoll) = registry.getUnrolledDVPs();

        assertEq(1, dvpsToRoll);
        assertEq(keccak256(abi.encodePacked(dvps)), keccak256(abi.encodePacked([address(dvp), address(0)])));

        vm.prank(admin);
        dvp.rollEpoch();

        (dvps, dvpsToRoll) = registry.getUnrolledDVPs();

        assertEq(0, dvpsToRoll);
        assertEq(keccak256(abi.encodePacked(dvps)), keccak256(abi.encodePacked([address(0), address(0)])));
        Utils.skipDay(true, vm);

        (dvps, dvpsToRoll) = registry.getUnrolledDVPs();

        assertEq(2, dvpsToRoll);
        assertEq(keccak256(abi.encodePacked(dvps)), keccak256(abi.encodePacked([address(dvp), address(dvp2)])));
    }
}
