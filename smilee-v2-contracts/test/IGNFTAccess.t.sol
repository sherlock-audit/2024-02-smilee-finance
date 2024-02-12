// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IVault} from "@project/interfaces/IVault.sol";
import {IDVPAccessNFT} from "@project/interfaces/IDVPAccessNFT.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {Vault} from "@project/Vault.sol";
import {IGAccessNFT} from "@project/periphery/IGAccessNFT.sol";
import {MockedIG} from "./mock/MockedIG.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";

/**
    @title Test case for priority deposits
 */
contract IGNFTAccessTest is Test {
    bytes4 constant _NFT_ACCESS_DENIED = bytes4(keccak256("NFTAccessDenied()"));
    bytes4 constant _NFT_ACCESS_CAP_EXCEEDED = bytes4(keccak256("NotionalCapExceeded()"));

    address _admin = address(0x1);
    address _alice = address(0x2);
    address _bob = address(0x3);
    MockedIG _ig;
    IGAccessNFT _nft;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.startPrank(_admin);
        AddressProvider ap = new AddressProvider(0);
        MockedRegistry registry = new MockedRegistry();
        registry.grantRole(registry.ROLE_ADMIN(), _admin);
        ap.grantRole(ap.ROLE_ADMIN(), _admin);
        _nft = new IGAccessNFT(address(ap));
        _nft.grantRole(_nft.ROLE_ADMIN(), _admin);
        ap.setDVPAccessNFT(address(_nft));
        ap.setRegistry(address(registry));
        vm.stopPrank();

        MockedVault vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, _admin, vm));
        TokenUtils.provideApprovedTokens(_admin, vault.baseToken(), _alice, address(vault), 100000e18, vm);
        TokenUtils.provideApprovedTokens(_admin, vault.baseToken(), _bob, address(vault), 100000e18, vm);

        vm.prank(_alice);
        vault.deposit(80000e18, _alice, 0);

        vm.startPrank(_admin);
        vault.grantRole(vault.ROLE_ADMIN(), _admin);
        vault.grantRole(vault.ROLE_EPOCH_ROLLER(), _admin);

        _ig = new MockedIG(address(vault), address(ap));
        _ig.grantRole(_ig.ROLE_ADMIN(), _admin);
        _ig.grantRole(_ig.ROLE_EPOCH_ROLLER(), _admin);

        MarketOracle mo = MarketOracle(ap.marketOracle());
        mo.setDelay(_ig.baseToken(), _ig.sideToken(), _ig.getEpoch().frequency, 0, true);

        registry.register(address(_ig));
        vault.setAllowedDVP(address(_ig));
        
        _ig.setNftAccessFlag(true);

        Utils.skipDay(true, vm);
        _ig.rollEpoch();
        vm.stopPrank();

        TokenUtils.provideApprovedTokens(_admin, vault.baseToken(), _alice, address(_ig), 100000e18, vm);
        TokenUtils.provideApprovedTokens(_admin, vault.baseToken(), _bob, address(_ig), 100000e18, vm);
    }  

    function testPriorityAccessFlag() public {
        assertEq(true, _ig.nftAccessFlag());

        vm.prank(_admin);
        _ig.setNftAccessFlag(false);
        assertEq(false, _ig.nftAccessFlag());

        vm.prank(_admin);
        _ig.setNftAccessFlag(true);
        assertEq(true, _ig.nftAccessFlag());
    }

    function testPriorityAccessDeniedWith0() public {
        vm.prank(_bob);
        vm.expectRevert(_NFT_ACCESS_DENIED);
        _ig.mint(_bob, 0, 1, 0, 0, 0.1e18, 0);
    }

    function testNFTAccessDeniedWithToken() public {
        vm.prank(_admin);
        uint256 tokenId = _nft.createToken(_bob, 1000e18);

        vm.prank(_alice);
        vm.expectRevert(_NFT_ACCESS_DENIED);
        _ig.mint(_alice, 0, 1, 0, 0, 0.1e18, 0);

        vm.prank(_alice);
         vm.expectRevert(_NFT_ACCESS_DENIED);
        _ig.mint(_alice, 0, 1, 0, 0, 0.1e18, tokenId);

        vm.prank(_alice);
        vm.expectRevert(_NFT_ACCESS_DENIED);
        _ig.mint(_alice, 0, 100e18, 100e18, 0, 0.1e18, 0);

        vm.prank(_alice);
        vm.expectRevert(_NFT_ACCESS_DENIED);
        _ig.mint(_alice, 0, 100e18, 100e18, 0, 0.1e18, tokenId);
    }

    function testNFTCapExceededWithToken(uint256 additionalAmount) public {
        vm.assume(additionalAmount > 0);
        vm.assume(additionalAmount < 100000e18);

        vm.prank(_admin);
        uint256 tokenId = _nft.createToken(_bob, 1000e18);

        (uint256 expected, ) = _ig.premium(0, 1000e18, additionalAmount);

        vm.prank(_bob);
        vm.expectRevert(_NFT_ACCESS_CAP_EXCEEDED);
        _ig.mint(_bob, 0, 1000e18, additionalAmount, expected, 0.1e18, tokenId);
    }

    function testPriorityAccessOk() public {
        vm.prank(_admin);
        uint256 tokenId = _nft.createToken(_bob, 100e18);

        vm.prank(_bob);
        _ig.mint(_bob, 0, 1, 0, 0, 0.1e18, tokenId);
    }
}
