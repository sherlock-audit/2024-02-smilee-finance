// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";
import {IRegistry} from "../../src/interfaces/IRegistry.sol";
import {EpochFrequency} from "../../src/lib/EpochFrequency.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {FeeManager} from "../../src/FeeManager.sol";
import {ChainlinkPriceOracle} from "../../src/providers/chainlink/ChainlinkPriceOracle.sol";
import {SwapAdapterRouter} from "../../src/providers/SwapAdapterRouter.sol";
import {IG} from "../../src/IG.sol";
import {Vault} from "../../src/Vault.sol";
import {TimeLockedFinanceParameters, TimeLockedFinanceValues} from "../../src/lib/FinanceIG.sol";
import {TimeLock, TimeLockedBool, TimeLockedUInt} from "../../src/lib/TimeLock.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/03_Factory.s.sol:DeployDVP --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv

        # NOTE: add the following to customize
        #       --sig 'createIGMarket(address,address,uint256)' <BASE_TOKEN_ADDRESS> <SIDE_TOKEN_ADDRESS> <EPOCH_FREQUENCY_IN_SECONDS> <FIRST_EPOCH_DURATION_IN_SECONDS>
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
    FeeManager internal _feeManager;
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
        _feeManager = FeeManager(_addressProvider.feeManager());
        console.log("AddressProvider", address(_addressProvider));
        console.log("FeeManager", _addressProvider.feeManager());
        console.log("Registry Address", _addressProvider.registry());
        _registry = IRegistry(_addressProvider.registry());
    }

    function run() external {}

    function createIGMarket(
        address baseToken,
        address sideToken,
        uint256 epochFrequency,
        uint256 firstEpochDuration
    ) public {
        vm.startBroadcast(_deployerPrivateKey);

        ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(_addressProvider.priceOracle());
        SwapAdapterRouter swapAdapter = SwapAdapterRouter(_addressProvider.exchangeAdapter());

        // Check if exists a record for the given tokens
        priceOracle.getPrice(baseToken, sideToken);
        if (swapAdapter.getAdapter(baseToken, sideToken) == address(0)) {
            revert("Swap Adapter hasn't been setted");
        }

        address vault = _createVault(baseToken, sideToken, epochFrequency, firstEpochDuration);
        address dvp = _createImpermanentGainDVP(vault);

        Vault(vault).setAllowedDVP(dvp);

        string memory sideTokenSymbol = IERC20Metadata(Vault(vault).sideToken()).symbol();

        bool deribitToken = _stringEquals(sideTokenSymbol, "ETH") || _stringEquals(sideTokenSymbol, "BTC");

        if (!deribitToken) {
            _setTimeLockedParameters(dvp);
        }

        _registry.register(dvp);

        uint8 decimals = IERC20Metadata(baseToken).decimals();
        FeeManager.FeeParams memory feeParams = FeeManager.FeeParams({
            timeToExpiryThreshold: 3600,
            minFeeBeforeTimeThreshold: (10 ** decimals) / 100, // 0.1
            minFeeAfterTimeThreshold: (10 ** decimals) / 100, // 0.1
            successFeeTier: 0.02e18,
            feePercentage: 0.0015e18,
            capPercentage: 0.125e18,
            maturityFeePercentage: 0.0015e18,
            maturityCapPercentage: 0.125e18
        });

        _setDVPFee(dvp, feeParams);

        vm.stopBroadcast();

        console.log("DVP deployed at", dvp);
        console.log("Vault deployed at", vault);
    }

    function _stringEquals(string memory s1, string memory s2) internal pure returns (bool) {
        // TBD: use abi.encodePacked(s) instead of bytes(s)
        return keccak256(bytes(s1)) == keccak256(bytes(s2));
    }

    function _createVault(
        address baseToken,
        address sideToken,
        uint256 epochFrequency,
        uint256 firstEpochDuration
    ) internal returns (address) {
        Vault vault = new Vault(baseToken, sideToken, epochFrequency, firstEpochDuration, address(_addressProvider));

        vault.grantRole(vault.ROLE_GOD(), _adminMultiSigAddress);
        vault.grantRole(vault.ROLE_ADMIN(), _deployerAddress);
        vault.renounceRole(vault.ROLE_GOD(), _deployerAddress);

        return address(vault);
    }

    function setDVPFee(
        address dvp,
        uint256 timeToExpiryThreshold,
        uint256 minFeeBeforeThreshold,
        uint256 minFeeAfterThreshold,
        uint256 successFeeTier,
        uint256 feePercentage,
        uint256 capPercertage,
        uint256 mFeePercentage,
        uint256 mCapPercentage
    ) public {
        FeeManager.FeeParams memory params = FeeManager.FeeParams(
            timeToExpiryThreshold,
            minFeeBeforeThreshold,
            minFeeAfterThreshold,
            successFeeTier,
            feePercentage,
            capPercertage,
            mFeePercentage,
            mCapPercentage
        );

        _setDVPFee(dvp, params);
    }

    function _setDVPFee(address dvp, FeeManager.FeeParams memory params) internal{
        vm.startBroadcast(_deployerPrivateKey);
        _feeManager.setDVPFee(dvp, params);
        vm.stopBroadcast();
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
}
