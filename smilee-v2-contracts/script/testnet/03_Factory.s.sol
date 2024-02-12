// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {EpochFrequency} from "../../src/lib/EpochFrequency.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {FeeManager} from "../../src/FeeManager.sol";
import {IG} from "../../src/IG.sol";
import {Vault} from "../../src/Vault.sol";
import {TimeLockedFinanceParameters, TimeLockedFinanceValues} from "../../src/lib/FinanceIG.sol";
import {TimeLock, TimeLockedBool, TimeLockedUInt} from "../../src/lib/TimeLock.sol";
// import {Registry} from "../../src/Registry.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/03_Factory.s.sol:DeployDVP --fork-url $RPC_LOCALNET [--broadcast] -vvvv
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/03_Factory.s.sol:DeployDVP --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv

        # NOTE: add the following to customize
        #       --sig 'createIGMarket(address,address,uint256)' <BASE_TOKEN_ADDRESS> <SIDE_TOKEN_ADDRESS> <EPOCH_FREQUENCY_IN_SECONDS>
 */
contract DeployDVP is EnhancedScript {
    using TimeLock for TimeLockedBool;
    using TimeLock for TimeLockedUInt;

    uint256 internal _deployerPrivateKey;
    address internal _deployerAddress;
    address internal _adminMultiSigAddress;
    address internal _epochRollerAddress;
    address internal _sUSD;
    AddressProvider internal _addressProvider;
    IRegistry internal _registry;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        _adminMultiSigAddress = vm.envAddress("ADMIN_MULTI_SIG_ADDRESS");
        _epochRollerAddress = vm.envAddress("EPOCH_ROLLER_ADDRESS");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _sUSD = _readAddress(txLogs, "TestnetToken");
        _addressProvider = AddressProvider(_readAddress(txLogs, "AddressProvider"));
        console.log("AddressProvider", address(_addressProvider));
        console.log("Registry Address", _addressProvider.registry());
        _registry = IRegistry(_addressProvider.registry());
    }

    function run() external {
        string memory txLogs = _getLatestTransactionLogs("02_Token.s.sol");
        address sideToken = _readAddress(txLogs, "TestnetToken");

        createIGMarket(_sUSD, sideToken, EpochFrequency.WEEKLY);
    }

    function createIGMarket(address baseToken, address sideToken, uint256 epochFrequency) public {
        vm.startBroadcast(_deployerPrivateKey);

        address vault = _createVault(baseToken, sideToken, epochFrequency);
        address dvp = _createImpermanentGainDVP(vault);

        Vault(vault).setAllowedDVP(dvp);
        console.log(address(_registry));

        string memory sideTokenSymbol = IERC20Metadata(Vault(vault).sideToken()).symbol();
        if (!_stringEquals(sideTokenSymbol, "sETH") && !_stringEquals(sideTokenSymbol, "sBTC")) {
            _setTimeLockedParameters(dvp);
        }

        _setDefaultFees(dvp);

        _registry.register(dvp);

        vm.stopBroadcast();

        console.log("DVP deployed at", dvp);
        console.log("Vault deployed at", vault);
    }

    function _stringEquals(string memory s1, string memory s2) internal pure returns (bool) {
        // TBD: use abi.encodePacked(s) instead of bytes(s)
        return keccak256(bytes(s1)) == keccak256(bytes(s2));
    }

    function _createVault(address baseToken, address sideToken, uint256 epochFrequency) internal returns (address) {
        Vault vault = new Vault(baseToken, sideToken, epochFrequency, epochFrequency, address(_addressProvider));

        vault.grantRole(vault.ROLE_GOD(), _adminMultiSigAddress);
        vault.grantRole(vault.ROLE_ADMIN(), _deployerAddress);
        vault.renounceRole(vault.ROLE_GOD(), _deployerAddress);

        return address(vault);
    }

    function _createImpermanentGainDVP(address vault) internal returns (address) {
        IG dvp = new IG(vault, address(_addressProvider));

        dvp.grantRole(dvp.ROLE_GOD(), _adminMultiSigAddress);
        dvp.grantRole(dvp.ROLE_ADMIN(), _deployerAddress);
        dvp.grantRole(dvp.ROLE_EPOCH_ROLLER(), _epochRollerAddress);
        dvp.renounceRole(dvp.ROLE_GOD(), _deployerAddress);

        return address(dvp);
    }

    function dvpUnregister(address dvpAddr) public {
        vm.startBroadcast(_deployerPrivateKey);
        _registry.unregister(dvpAddr);
        vm.stopBroadcast();
    }

    // function setTradCompFees() public {
    //     vm.startBroadcast(_deployerPrivateKey);
    //     FeeManager feeMan = FeeManager(_addressProvider.feeManager());
    //     feeMan.setFeePercentage(0.00015e18);
    //     feeMan.setCapPercentage(0.05e18);
    //     feeMan.setMaturityFeePercentage(0.000075e18);
    //     feeMan.setMaturityCapPercentage(0.05e18);
    //     vm.stopBroadcast();
    // }

    function _setDefaultFees(address dvpAddr) internal {
        FeeManager(_addressProvider.feeManager()).setDVPFee(
            dvpAddr,
            FeeManager.FeeParams(3600, 0, 0, 0, 0.0035e18, 0.125e18, 0.0015e18, 0.125e18)
        );
    }

    function setTimeLockedParameters(address igAddress) public {
        vm.startBroadcast(_deployerPrivateKey);
        _setTimeLockedParameters(igAddress);
        vm.stopBroadcast();
    }

    function _setTimeLockedParameters(address igAddress) internal {
        IG ig = IG(igAddress);
        TimeLockedFinanceValues memory currentValues = _getTimeLockedFinanceParameters(ig);
        currentValues.useOracleImpliedVolatility = false;

        ig.setParameters(currentValues);
    }

    function _getTimeLockedFinanceParameters(
        IG ig
    ) private view returns (TimeLockedFinanceValues memory currentValues) {
        (, , , , , , TimeLockedFinanceParameters memory igParams, , ) = ig.financeParameters();
        currentValues = TimeLockedFinanceValues({
            sigmaMultiplier: igParams.sigmaMultiplier.get(),
            tradeVolatilityUtilizationRateFactor: igParams.tradeVolatilityUtilizationRateFactor.get(),
            tradeVolatilityTimeDecay: igParams.tradeVolatilityTimeDecay.get(),
            volatilityPriceDiscountFactor: igParams.volatilityPriceDiscountFactor.get(),
            useOracleImpliedVolatility: igParams.useOracleImpliedVolatility.get()
        });
    }

    // function fixTradingCompFinanceParams() public {
    //     vm.startBroadcast(_deployerPrivateKey);
    //     Registry registry = Registry(_addressProvider.registry());
    //     address[] memory sideTokens = registry.getSideTokens();
    //     uint256 numSideTokens = sideTokens.length;
    //     console.log("Num of side tokens: ", numSideTokens);
    //     for (uint256 i = 0; i < numSideTokens; i++) {
    //         address sideTokenAddr = sideTokens[i];
    //         string memory sideTokenSymbol = IERC20Metadata(sideTokenAddr).symbol();
    //         console.log("Working on ", sideTokenSymbol);
    //         if (_stringEquals(sideTokenSymbol, "sETH") || _stringEquals(sideTokenSymbol, "sBTC")) {
    //             continue;
    //         }
    //         address[] memory dvps = registry.getDvpsBySideToken(sideTokenAddr);
    //         uint256 numDVPs = dvps.length;
    //         console.log("- Num of DVPs: ", numDVPs);
    //         for (uint256 j = 0; j < numDVPs; j++) {
    //             address dvpAddr = dvps[j];
    //             console.log("-- Fixing DVP: ", dvpAddr);
    //             _setTimeLockedParameters(dvpAddr);
    //         }
    //     }
    //     vm.stopBroadcast();
    // }
}
