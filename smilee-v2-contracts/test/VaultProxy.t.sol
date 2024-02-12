// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultProxy} from "@project/interfaces/IVaultProxy.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {VaultProxy} from "@project/periphery/VaultProxy.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";
import {MockedVault} from "./mock/MockedVault.sol";

/**
    @notice A sample non-Vault contract.
 */
contract NonVault {
    /**
     * Function used to skip coverage on this file
     */
    function testCoverageSkip() private view {}
}

/**
    @notice A sample contract with `IVault.baseToken()` function impl.
 */
contract NonVaultBaseToken is NonVault {
    address private _baseToken;

    function setBaseToken(address token) external {
        _baseToken = token;
    }

    function baseToken() public view returns (address) {
        return _baseToken;
    }
}

/**
    @notice A sample contract partially implementing IVault, to check if
            deposits can be hijacked. See VaultProxyTest.testDepositHijack().
 */
contract Receiver is NonVaultBaseToken {
    address private _receiver;

    constructor(address receiver) {
        _receiver = receiver;
    }

    function deposit(uint256 amount, address creditor) external {
        creditor;
        IERC20(baseToken()).transferFrom(msg.sender, address(this), amount);
        IERC20(baseToken()).transfer(_receiver, amount);
    }
}

contract VaultProxyTest is Test {
    address _tokenAdmin = address(0x1);
    address _alice = address(0x2);
    address _bob = address(0x3);
    address _charlie = address(0x4);
    TestnetToken _baseToken;
    TestnetToken _sideToken;
    MockedVault _vault0;
    MockedVault _vault1;
    VaultProxy _proxy;

    bytes4 constant DEPOSIT_TO_NON_VAULT_CONTRACT = bytes4(keccak256("DepositToNonVaultContract()"));

    /**
        Creates a couple of vaults.
     */
    function setUp() public {
        vm.warp(EpochFrequency.REF_TS + 1);

        vm.startPrank(_tokenAdmin);
        MockedRegistry registry = new MockedRegistry();
        registry.grantRole(registry.ROLE_ADMIN(), _tokenAdmin);

        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), _tokenAdmin);
        _proxy = new VaultProxy(address(ap));
        ap.setRegistry(address(registry));
        ap.setVaultProxy(address(_proxy));
        vm.stopPrank();

        _vault0 = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, _tokenAdmin, vm));
        _baseToken = TestnetToken(_vault0.baseToken());
        _sideToken = TestnetToken(_vault0.sideToken());
        _vault1 = MockedVault(
            VaultUtils.createVaultFromTokens(
                address(_baseToken),
                address(_sideToken),
                EpochFrequency.WEEKLY,
                ap,
                _tokenAdmin,
                vm
            )
        );

        vm.startPrank(_tokenAdmin);
        _vault0.grantRole(_vault0.ROLE_ADMIN(), _tokenAdmin);
        _vault0.grantRole(_vault0.ROLE_EPOCH_ROLLER(), _tokenAdmin);
        _vault1.grantRole(_vault1.ROLE_ADMIN(), _tokenAdmin);
        _vault1.grantRole(_vault1.ROLE_EPOCH_ROLLER(), _tokenAdmin);
        vm.stopPrank();

        vm.prank(_tokenAdmin);
        registry.registerVault(address(_vault0));
    }

    /**
        Check simple deposit works
     */
    function testDeposit() public {
        TokenUtils.provideApprovedTokens(_tokenAdmin, address(_baseToken), _alice, address(_proxy), 100, vm);
        vm.prank(_alice);
        _proxy.deposit(IVaultProxy.DepositParams(address(_vault0), _alice, 100, 0));
        Utils.skipDay(false, vm);
        vm.prank(_tokenAdmin);
        _vault0.rollEpoch();

        (, uint256 unredeemedShares) = _vault0.shareBalances(_alice);
        assertEq(100, _vault0.totalSupply());
        assertEq(100, unredeemedShares);
    }

    /**
        Check multiple deposits can be done with a single approval
     */
    function testMultipleDeposit() public {
        TokenUtils.provideApprovedTokens(_tokenAdmin, address(_baseToken), _alice, address(_proxy), 200, vm);

        vm.prank(_alice);
        _proxy.deposit(IVaultProxy.DepositParams(address(_vault0), _alice, 100, 0));

        vm.prank(_alice);
        _proxy.deposit(IVaultProxy.DepositParams(address(_vault1), _alice, 100, 0));

        Utils.skipDay(false, vm);
        vm.prank(_tokenAdmin);
        _vault0.rollEpoch();

        for (uint256 i = 0; i < 6; i++) {
            Utils.skipDay(false, vm);
        }
        vm.prank(_tokenAdmin);
        _vault1.rollEpoch();

        (, uint256 unredeemedShares0) = _vault0.shareBalances(_alice);
        (, uint256 unredeemedShares1) = _vault1.shareBalances(_alice);
        assertEq(100, _vault0.totalSupply());
        assertEq(100, unredeemedShares0);

        assertEq(100, _vault1.totalSupply());
        assertEq(100, unredeemedShares1);
    }

    /**
        Check what happens when calling `VaultProxy.deposit()` with non-Vault
        contract.
     */
    function testDepositToNonVault() public {
        TokenUtils.provideApprovedTokens(_tokenAdmin, address(_baseToken), _alice, address(_proxy), 200, vm);

        NonVault receiver = new NonVault();

        vm.prank(_alice);
        // vm.expectRevert("Contract does not have fallback nor receive functions");
        vm.expectRevert(DEPOSIT_TO_NON_VAULT_CONTRACT);
        _proxy.deposit(IVaultProxy.DepositParams(address(receiver), _alice, 100, 0));
    }

    /**
        Check a deposit cannot be hijacked to a on purpose created contract
     */
    function testDepositHijack() public {
        TokenUtils.provideApprovedTokens(_tokenAdmin, address(_baseToken), _alice, address(_proxy), 200, vm);

        Receiver receiver = new Receiver(_charlie);
        receiver.setBaseToken(address(_baseToken));

        vm.prank(_alice);
        vm.expectRevert(DEPOSIT_TO_NON_VAULT_CONTRACT);
        _proxy.deposit(IVaultProxy.DepositParams(address(receiver), _alice, 100, 0));
    }
}
