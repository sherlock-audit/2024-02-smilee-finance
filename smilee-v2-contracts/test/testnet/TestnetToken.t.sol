// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {MockedRegistry} from "../mock/MockedRegistry.sol";

contract TestnetTokenTest is Test {
    bytes4 constant _NOT_INITIALIZED = bytes4(keccak256("NotInitialized()"));
    bytes4 constant _UNAUTHORIZED = bytes4(keccak256("Unauthorized()"));

    AddressProvider _addressProvider;
    address _swapper = address(0x2);

    address _admin = address(0x3);
    address _alice = address(0x4);
    address _bob = address(0x5);

    function setUp() public {
        vm.startPrank(_admin);
        MockedRegistry registry = new MockedRegistry();
        registry.grantRole(registry.ROLE_ADMIN(), _admin);

        _addressProvider = new AddressProvider(0);
        _addressProvider.grantRole(_addressProvider.ROLE_ADMIN(), _admin);
        _addressProvider.setRegistry(address(registry));
        _addressProvider.setExchangeAdapter(_swapper);
        vm.stopPrank();
    }

    function testCantMintNotInit() public {
        vm.prank(_admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        vm.expectRevert(_NOT_INITIALIZED);
        token.mint(_admin, 100);
    }

    // NOTE: it doesn't make sense to test _NOT_INITIALIZED for burn and transfers as you can't mint.

    function testCantInit() public {
        vm.prank(_admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");

        vm.expectRevert("Ownable: caller is not the owner");
        token.setAddressProvider(address(_addressProvider));
    }

    function testInit() public {
        vm.startPrank(_admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setAddressProvider(address(_addressProvider));
        vm.stopPrank();

        assertEq(address(_addressProvider), token.getAddressProvider());
    }

    function testCantMintUnauth() public {
        vm.startPrank(_admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setAddressProvider(address(_addressProvider));
        vm.stopPrank();

        vm.prank(_alice);
        vm.expectRevert(_UNAUTHORIZED);
        token.mint(_alice, 100);
    }

    function testMint() public {
        vm.startPrank(_admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setAddressProvider(address(_addressProvider));
        vm.stopPrank();

        vm.prank(_admin);
        token.mint(_alice, 100);
        assertEq(100, token.balanceOf(_alice));

        vm.prank(_swapper);
        token.mint(_alice, 100);
        assertEq(200, token.balanceOf(_alice));
    }

    function testCantBurnUnauth() public {
        vm.startPrank(_admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setAddressProvider(address(_addressProvider));
        token.mint(_alice, 100);
        vm.stopPrank();

        vm.prank(_alice);
        vm.expectRevert(_UNAUTHORIZED);
        token.burn(_alice, 100);
    }

    function testBurn() public {
        vm.startPrank(_admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setAddressProvider(address(_addressProvider));
        token.mint(_alice, 100);
        vm.stopPrank();

        assertEq(100, token.balanceOf(_alice));

        vm.prank(_swapper);
        token.burn(_alice, 100);
        assertEq(0, token.balanceOf(_alice));
    }

    function testCantTransfer() public {
        vm.startPrank(_admin);
        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setAddressProvider(address(_addressProvider));
        token.mint(_alice, 100);
        vm.stopPrank();

        vm.prank(_alice);
        vm.expectRevert(_UNAUTHORIZED);
        token.transfer(_bob, 100);

        vm.prank(_bob);
        vm.expectRevert(_UNAUTHORIZED);
        token.transferFrom(_alice, _bob, 100);

        vm.prank(_admin);
        vm.expectRevert("ERC20: insufficient allowance");
        token.transferFrom(_alice, _bob, 100);
    }

    function testTransfer() public {
        vm.startPrank(_admin);

        TestnetToken token = new TestnetToken("Testnet USD", "stUSD");
        token.setAddressProvider(address(_addressProvider));
        token.mint(_alice, 100);

        address vaultAddress = address(0x42);
        MockedRegistry registry = MockedRegistry(_addressProvider.registry());
        registry.registerVault(vaultAddress);

        vm.stopPrank();

        vm.prank(_alice);
        token.approve(vaultAddress, 100);

        vm.prank(vaultAddress);
        token.transferFrom(_alice, vaultAddress, 100);
        assertEq(100, token.balanceOf(vaultAddress));
    }
}
