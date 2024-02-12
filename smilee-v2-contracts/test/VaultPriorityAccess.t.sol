// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IVault} from "@project/interfaces/IVault.sol";
import {IVaultAccessNFT} from "@project/interfaces/IVaultAccessNFT.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {Vault} from "@project/Vault.sol";
import {VaultAccessNFT} from "@project/periphery/VaultAccessNFT.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";

/**
    @title Test case for priority deposits
 */
contract VaultPriorityAccessTest is Test {
    bytes4 constant _PRIORITY_ACCESS_DENIED = bytes4(keccak256("PriorityAccessDenied()"));

    address _admin = address(0x1);
    address _alice = address(0x2);
    address _bob = address(0x3);
    MockedVault _vault;
    VaultAccessNFT _nft;

    function setUp() public {
        vm.warp(EpochFrequency.REF_TS);

        vm.startPrank(_admin);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), _admin);
        _nft = new VaultAccessNFT(address(ap));
        _nft.grantRole(_nft.ROLE_ADMIN(), _admin);
        ap.setVaultAccessNFT(address(_nft));
        vm.stopPrank();

        _vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, _admin, vm));
        TokenUtils.provideApprovedTokens(_admin, _vault.baseToken(), _alice, address(_vault), 1000e18, vm);
        TokenUtils.provideApprovedTokens(_admin, _vault.baseToken(), _bob, address(_vault), 1000e18, vm);

        vm.startPrank(_admin);
        _vault.grantRole(_vault.ROLE_ADMIN(), _admin);
        _vault.grantRole(_vault.ROLE_EPOCH_ROLLER(), _admin);
        vm.stopPrank();

        vm.prank(_admin);
        _vault.setPriorityAccessFlag(true);
    }

    function testPriorityAccessFlag() public {
        assertEq(true, _vault.priorityAccessFlag());

        vm.prank(_admin);
        _vault.setPriorityAccessFlag(false);
        assertEq(false, _vault.priorityAccessFlag());

        vm.prank(_admin);
        _vault.setPriorityAccessFlag(true);
        assertEq(true, _vault.priorityAccessFlag());
    }

    function testPriorityAccessDeniedWith0() public {
        vm.prank(_alice);
        vm.expectRevert(_PRIORITY_ACCESS_DENIED);
        _vault.deposit(100e18, _alice, 0);
    }

    function testPriorityAccessDeniedWithToken() public {
        vm.prank(_admin);
        uint256 tokenId = _nft.createToken(_bob, 100e18);

        vm.prank(_alice);
        vm.expectRevert(_PRIORITY_ACCESS_DENIED);
        _vault.deposit(100e18, _alice, 0);

        vm.prank(_alice);
        vm.expectRevert(_PRIORITY_ACCESS_DENIED);
        _vault.deposit(100e18, _alice, tokenId);

        vm.prank(_alice);
        vm.expectRevert(_PRIORITY_ACCESS_DENIED);
        _vault.deposit(100e18, address(0x0), 0);

        vm.prank(_alice);
        vm.expectRevert(_PRIORITY_ACCESS_DENIED);
        _vault.deposit(100e18, address(0x0), tokenId);
    }

    function testPriorityAccessOk() public {
        vm.prank(_admin);
        uint256 tokenId = _nft.createToken(_bob, 100e18);

        vm.prank(_bob);
        _vault.deposit(1e18, _bob, tokenId);

        Utils.skipDay(true, vm);
        vm.prank(_admin);
        _vault.rollEpoch();

        (uint256 heldByAccount, uint256 heldByVault) = _vault.shareBalances(_bob);
        assertEq(99e18, _nft.priorityAmount(tokenId));
        assertEq(1e18, _vault.totalSupply());
        assertEq(0, heldByAccount);
        assertEq(1e18, heldByVault);
    }

    function testNftBurn() public {
        vm.prank(_admin);
        uint256 tokenId = _nft.createToken(_bob, 100e18);

        vm.startPrank(_bob);
        _vault.deposit(1e18, _bob, tokenId);
        _nft.transferFrom(_bob, _alice, tokenId);
        _vault.deposit(99e18, _alice, tokenId);
        vm.stopPrank();

        Utils.skipDay(true, vm);
        vm.prank(_admin);
        _vault.rollEpoch();

        (uint256 heldByAccountAlice, uint256 heldByVaultAlice) = _vault.shareBalances(_alice);
        (uint256 heldByAccountBob, uint256 heldByVaultBob) = _vault.shareBalances(_bob);

        vm.expectRevert("ERC721: invalid token ID");
        _nft.priorityAmount(tokenId);

        assertEq(100e18, _vault.totalSupply());
        assertEq(0, heldByAccountAlice);
        assertEq(0, heldByAccountBob);
        assertEq(99e18, heldByVaultAlice);
        assertEq(1e18, heldByVaultBob);
    }
}
