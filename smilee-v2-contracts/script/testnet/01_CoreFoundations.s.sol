// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {FeeManager} from "../../src/FeeManager.sol";
import {MarketOracle} from "../../src/MarketOracle.sol";
import {PositionManager} from "../../src/periphery/PositionManager.sol";
import {Registry} from "../../src/periphery/Registry.sol";
import {VaultProxy} from "../../src/periphery/VaultProxy.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {TestnetSwapAdapter} from "../../src/testnet/TestnetSwapAdapter.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/01_CoreFoundations.s.sol:DeployCoreFoundations --fork-url $RPC_LOCALNET --broadcast -vvvv
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/01_CoreFoundations.s.sol:DeployCoreFoundations --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv
 */
contract DeployCoreFoundations is Script {
    uint256 internal _deployerPrivateKey;
    address internal _deployerAddress;
    address internal _adminMultiSigAddress;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        _adminMultiSigAddress = vm.envAddress("ADMIN_MULTI_SIG_ADDRESS");
    }

    // NOTE: this is the script entrypoint
    function run() external {
        // The broadcast will records the calls and contract creations made and will replay them on-chain.
        // For reference, the broadcast transaction logs will be stored in the broadcast directory.
        vm.startBroadcast(_deployerPrivateKey);
        _doSomething();
        vm.stopBroadcast();
    }

    function _doSomething() internal {
        TestnetToken sUSD = new TestnetToken("Smilee USD", "sUSD");
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_GOD(), _adminMultiSigAddress);
        ap.grantRole(ap.ROLE_ADMIN(), _deployerAddress);
        //ap.renounceRole(ap.ROLE_GOD(), _deployerAddress);

        TestnetPriceOracle priceOracle = new TestnetPriceOracle(address(sUSD));
        ap.setPriceOracle(address(priceOracle));

        VaultProxy vaultProxy = new VaultProxy(address(ap));
        ap.setVaultProxy(address(vaultProxy));

        MarketOracle marketOracle = new MarketOracle();
        marketOracle.grantRole(marketOracle.ROLE_GOD(), _adminMultiSigAddress);
        marketOracle.grantRole(marketOracle.ROLE_ADMIN(), _deployerAddress);
        //marketOracle.renounceRole(marketOracle.ROLE_GOD(), _deployerAddress);
        ap.setMarketOracle(address(marketOracle));

        TestnetSwapAdapter swapper = new TestnetSwapAdapter(address(priceOracle));
        ap.setExchangeAdapter(address(swapper));

        FeeManager feeManager = new FeeManager(0);
        feeManager.grantRole(feeManager.ROLE_GOD(), _adminMultiSigAddress);
        feeManager.grantRole(feeManager.ROLE_ADMIN(), _deployerAddress);
        //feeManager.renounceRole(feeManager.ROLE_GOD(), _deployerAddress);
        ap.setFeeManager(address(feeManager));

        Registry registry = new Registry();
        registry.grantRole(registry.ROLE_GOD(), _adminMultiSigAddress);
        registry.grantRole(registry.ROLE_ADMIN(), _deployerAddress);
        //registry.renounceRole(registry.ROLE_GOD(), _deployerAddress);
        ap.setRegistry(address(registry));

        sUSD.setAddressProvider(address(ap));
        PositionManager pm = new PositionManager();
        ap.setDvpPositionManager(address(pm));

        // ap.renounceRole(ap.ROLE_ADMIN(), _deployerAddress);
    }
}
