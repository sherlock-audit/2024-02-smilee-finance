// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {ChainlinkPriceOracle} from "@project/providers/chainlink/ChainlinkPriceOracle.sol";
import {UniswapAdapter} from "@project/providers/uniswap/UniswapAdapter.sol";
import {SwapAdapterRouter} from "@project/providers/SwapAdapterRouter.sol";
import {PositionManager} from "@project/periphery/PositionManager.sol";
import {IGAccessNFT} from "@project/periphery/IGAccessNFT.sol";
import {Registry} from "@project/periphery/Registry.sol";
import {VaultAccessNFT} from "@project/periphery/VaultAccessNFT.sol";
import {VaultProxy} from "@project/periphery/VaultProxy.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/mainnet/01_CoreFoundations.s.sol:DeployCoreFoundations --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv
 */
contract DeployCoreFoundations is Script {
    uint256 internal _deployerPrivateKey;
    address internal _deployerAddress;
    address internal _godAddress;
    address internal _adminAddress;
    bool internal _deployerIsGod;
    bool internal _deployerIsAdmin;
    address internal _uniswapFactoryAddress;

    error ZeroAddress(string name);

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        _godAddress = vm.envAddress("GOD_ADDRESS");
        _adminAddress = vm.envAddress("ADMIN_ADDRESS");

        _deployerIsGod = (_deployerAddress == _godAddress);
        _deployerIsAdmin = (_deployerAddress == _adminAddress);

        _uniswapFactoryAddress = vm.envAddress("UNISWAP_FACTORY_ADDRESS");
    }

    // NOTE: this is the script entrypoint
    function run() external {
        _checkZeroAddress(_deployerAddress, "DEPLOYER_ADDRESS");
        _checkZeroAddress(_godAddress, "GOD_ADDRESS");
        _checkZeroAddress(_adminAddress, "ADMIN_ADDRESS");
        _checkZeroAddress(_uniswapFactoryAddress, "UNISWAP_FACTORY_ADDRESS");

        vm.startBroadcast(_deployerPrivateKey);
        _deployMainContracts();
        vm.stopBroadcast();
    }

    function _checkZeroAddress(address addr, string memory name) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress(name);
        }
    }

    function _deployMainContracts() internal {
        // Address provider:
        AddressProvider ap = new AddressProvider(1 days);
        ap.grantRole(ap.ROLE_GOD(), _godAddress);
        ap.grantRole(ap.ROLE_ADMIN(), _adminAddress);
        ap.grantRole(ap.ROLE_ADMIN(), _deployerAddress); // TMP
        if (!_deployerIsGod) {
            ap.renounceRole(ap.ROLE_GOD(), _deployerAddress);
        }

        // Price oracle:
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle();
        priceOracle.grantRole(priceOracle.ROLE_GOD(), _godAddress);
        priceOracle.grantRole(priceOracle.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            priceOracle.renounceRole(priceOracle.ROLE_GOD(), _deployerAddress);
        }
        ap.setPriceOracle(address(priceOracle));

        // Vault proxy:
        VaultProxy vaultProxy = new VaultProxy(address(ap));
        ap.setVaultProxy(address(vaultProxy));

        // Market oracle:
        MarketOracle marketOracle = new MarketOracle();
        marketOracle.grantRole(marketOracle.ROLE_GOD(), _godAddress);
        marketOracle.grantRole(marketOracle.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            marketOracle.renounceRole(marketOracle.ROLE_GOD(), _deployerAddress);
        }
        ap.setMarketOracle(address(marketOracle));

        // Swap router:
        SwapAdapterRouter swapAdapterRouter = new SwapAdapterRouter(address(priceOracle), 6 hours);
        swapAdapterRouter.grantRole(swapAdapterRouter.ROLE_GOD(), _godAddress);
        swapAdapterRouter.grantRole(swapAdapterRouter.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            swapAdapterRouter.renounceRole(swapAdapterRouter.ROLE_GOD(), _deployerAddress);
        }
        ap.setExchangeAdapter(address(swapAdapterRouter));

        // Uniswap adapter:
        UniswapAdapter uniswapAdapter = new UniswapAdapter(address(swapAdapterRouter), _uniswapFactoryAddress, 6 hours);
        uniswapAdapter.grantRole(uniswapAdapter.ROLE_GOD(), _godAddress);
        uniswapAdapter.grantRole(uniswapAdapter.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            uniswapAdapter.renounceRole(uniswapAdapter.ROLE_GOD(), _deployerAddress);
        }
        console.log("UniswapAdapter deployed at", address(uniswapAdapter));

        // Fee manager:
        FeeManager feeManager = new FeeManager(6 hours);
        feeManager.grantRole(feeManager.ROLE_GOD(), _godAddress);
        feeManager.grantRole(feeManager.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            feeManager.renounceRole(feeManager.ROLE_GOD(), _deployerAddress);
        }
        ap.setFeeManager(address(feeManager));

        // Registry:
        Registry registry = new Registry();
        registry.grantRole(registry.ROLE_GOD(), _godAddress);
        registry.grantRole(registry.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            registry.renounceRole(registry.ROLE_GOD(), _deployerAddress);
        }
        ap.setRegistry(address(registry));

        // DVP positions manager:
        PositionManager pm = new PositionManager();
        ap.setDvpPositionManager(address(pm));

        // Vault access NFT:
        VaultAccessNFT vaultAccess = new VaultAccessNFT(address(ap));
        vaultAccess.grantRole(vaultAccess.ROLE_GOD(), _godAddress);
        vaultAccess.grantRole(vaultAccess.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            vaultAccess.renounceRole(vaultAccess.ROLE_GOD(), _deployerAddress);
        }
        ap.setVaultAccessNFT(address(vaultAccess));

        // DVP access NFT:
        IGAccessNFT igAccess = new IGAccessNFT(address(ap));
        igAccess.grantRole(igAccess.ROLE_GOD(), _godAddress);
        igAccess.grantRole(igAccess.ROLE_ADMIN(), _adminAddress);
        if (!_deployerIsGod) {
            igAccess.renounceRole(igAccess.ROLE_GOD(), _deployerAddress);
        }
        ap.setDVPAccessNFT(address(igAccess));

        if (!_deployerIsAdmin) {
            ap.renounceRole(ap.ROLE_ADMIN(), _deployerAddress);
        }
    }
}
