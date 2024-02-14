// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IHevm} from "../utils/IHevm.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {AddressProviderUtils} from "./AddressProviderUtils.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {MockedRegistry} from "../../mock/MockedRegistry.sol";
import {MockedIG} from "../../mock/MockedIG.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "@project/interfaces/IVault.sol";
import {IPriceOracle} from "@project/interfaces/IPriceOracle.sol";

library EchidnaVaultUtils {
    function createVault(
        address baseToken,
        address tokenAdmin,
        uint8 sideTokenDecimals,
        AddressProvider addressProvider,
        uint256 epochFrequency,
        IHevm vm
    ) public returns (address) {
        TestnetToken sideToken = new TestnetToken("SideTestToken", "STT");
        sideToken.setDecimals(sideTokenDecimals);
        sideToken.setAddressProvider(address(addressProvider));
        TestnetPriceOracle apPriceOracle = TestnetPriceOracle(addressProvider.priceOracle());

        vm.prank(tokenAdmin);
        apPriceOracle.setTokenPrice(address(sideToken), 1 ether);

        MockedVault vault = new MockedVault(
            address(baseToken),
            address(sideToken),
            epochFrequency,
            address(addressProvider)
        );
        return address(vault);
    }

    function registerVault(address admin, address vault, AddressProvider addressProvider, IHevm vm) public {
        MockedRegistry apRegistry = MockedRegistry(addressProvider.registry());
        vm.prank(admin);
        apRegistry.registerVault(vault);
    }

    function grantAdminRole(address admin, address vault_) public {
        MockedVault vault = MockedVault(vault_);
        bytes32 role = vault.ROLE_ADMIN();
        vault.grantRole(role, admin);
    }

    function grantEpochRollerRole(address admin, address roller, address vault_, IHevm vm) public {
        MockedVault vault = MockedVault(vault_);
        bytes32 role = vault.ROLE_EPOCH_ROLLER();
        vm.prank(admin);
        vault.grantRole(role, roller);
    }

    function rollEpoch(address admin, MockedVault vault, IHevm vm) public {
        vm.prank(admin);
        vault.rollEpoch();
    }

    function igSetup(address admin, MockedVault vault, AddressProvider ap, IHevm vm) public returns (address) {

        MockedIG ig = new MockedIG(address(vault), address(ap));

        bytes32 roleAdmin = ig.ROLE_ADMIN();
        bytes32 roleRoller = ig.ROLE_EPOCH_ROLLER();

        ig.grantRole(roleAdmin, admin);
        vm.prank(admin);
        ig.grantRole(roleRoller, admin);

        MockedRegistry registry = MockedRegistry(ap.registry());

        vm.prank(admin);
        registry.registerDVP(address(ig));

        vm.prank(admin);
        vault.setAllowedDVP(address(ig));

        return address(ig);
    }

    function getSideTokenValue(IVault vault, AddressProvider addressProvider) internal view returns (uint256 sideTokenValue) {
        uint256 sideTokenAmount = IERC20(vault.sideToken()).balanceOf(address(vault));
        uint256 sideTokenDecimals = IERC20Metadata(vault.sideToken()).decimals();
        uint256 baseTokenDecimals = IERC20Metadata(vault.baseToken()).decimals();
        uint256 price = IPriceOracle(addressProvider.priceOracle()).getPrice(vault.sideToken(), vault.baseToken());
        sideTokenValue = (sideTokenAmount * price) / 10 ** (18 + sideTokenDecimals - baseTokenDecimals);
    }

    function getAssetsValue(IVault vault, AddressProvider addressProvider) internal view returns (uint256) {
        uint256 baseTokens = IERC20(vault.baseToken()).balanceOf(address(vault));
        uint256 sideTokenValue = getSideTokenValue(vault, addressProvider);
        return baseTokens + sideTokenValue;
    }
}
