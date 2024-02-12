// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IHevm} from "../utils/IHevm.sol";
import {Vm} from "forge-std/Vm.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {TestnetSwapAdapter} from "@project/testnet/TestnetSwapAdapter.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {MockedRegistry} from "../../mock/MockedRegistry.sol";

library AddressProviderUtils {
    function initialize(
        address admin,
        AddressProvider addressProvider,
        address baseToken,
        bool dexHasSlippage,
        IHevm vm
    ) public {
        address registryAddress = addressProvider.registry();
        if (registryAddress == address(0)) {
            MockedRegistry registry = new MockedRegistry();
            registry.grantRole(registry.ROLE_ADMIN(), admin);
            registryAddress = address(registry);
            vm.prank(admin);
            addressProvider.setRegistry(registryAddress);
        }

        address priceOracleAddress = addressProvider.priceOracle();
        if (priceOracleAddress == address(0)) {
            TestnetPriceOracle priceOracle = new TestnetPriceOracle(address(baseToken));
            priceOracle.transferOwnership(admin);
            priceOracleAddress = address(priceOracle);
            vm.prank(admin);
            addressProvider.setPriceOracle(priceOracleAddress);
        }

        address feeManagerAddress = addressProvider.feeManager();
        if (feeManagerAddress == address(0)) {
            FeeManager feeManager = new FeeManager(0);
            feeManager.grantRole(feeManager.ROLE_ADMIN(), admin);
            feeManagerAddress = address(feeManager);
            vm.prank(admin);
            addressProvider.setFeeManager(feeManagerAddress);
        }

        address marketOracleAddress = addressProvider.marketOracle();
        if (marketOracleAddress == address(0)) {
            MarketOracle marketOracle = new MarketOracle();
            marketOracle.grantRole(marketOracle.ROLE_ADMIN(), admin);
            marketOracleAddress = address(marketOracle);
            vm.prank(admin);
            addressProvider.setMarketOracle(marketOracleAddress);
        }

        address dexAddress = addressProvider.exchangeAdapter();
        if (dexAddress == address(0)) {
            TestnetSwapAdapter exchange = new TestnetSwapAdapter(priceOracleAddress);
            exchange.transferOwnership(admin);
            dexAddress = address(exchange);
            if (dexHasSlippage) {
                vm.prank(admin);
                // set random slippage between [-1, 3] %
                exchange.setSlippage(0, -0.01e18, 0.03e18);
            }
            vm.prank(admin);
            addressProvider.setExchangeAdapter(dexAddress);
        }
    }

    function getFeeManager(AddressProvider ap) public view returns (FeeManager feeManager) {
        feeManager = FeeManager(ap.feeManager());
    }
}
