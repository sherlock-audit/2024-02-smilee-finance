// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {IHevm} from "../utils/IHevm.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {TestnetToken} from "@project/testnet/TestnetToken.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {AddressProviderUtils} from "../lib/AddressProviderUtils.sol";
import {EchidnaVaultUtils} from "../lib/EchidnaVaultUtils.sol";
import {MockedVault} from "../../mock/MockedVault.sol";
import {MockedIG} from "../../mock/MockedIG.sol";
import {Parameters} from "../utils/Parameters.sol";
import {FeeManager} from "@project/FeeManager.sol";

abstract contract Setup is Parameters {
    event Debug(string);
    event DebugUInt(string, uint256);
    event DebugAddr(string, address);
    event DebugBool(string, bool);

    address internal constant VM_ADDRESS_SETUP = address(uint160(uint256(keccak256("hevm cheat code"))));
    IHevm internal hevm;

    address internal admin = address(0xf9c);

    MockedVault internal vault;
    MockedIG internal ig;
    AddressProvider ap;
    TestnetToken baseToken;

    constructor() {
        hevm = IHevm(VM_ADDRESS_SETUP);

        BASE_TOKEN_DECIMALS = 18;
        SIDE_TOKEN_DECIMALS = 18;
        EPOCH_FREQUENCY = EpochFrequency.DAILY;
        USE_ORACLE_IMPL_VOL = false;
        FLAG_SLIPPAGE = false;
    }

    function deploy() internal {
        hevm.warp(EpochFrequency.REF_TS + 1);
        ap = new AddressProvider(0);

        ap.grantRole(ap.ROLE_ADMIN(), admin);
        baseToken = new TestnetToken("BaseTestToken", "BTT");
        baseToken.setDecimals(BASE_TOKEN_DECIMALS);
        baseToken.transferOwnership(admin);
        hevm.prank(admin);
        baseToken.setAddressProvider(address(ap));

        AddressProviderUtils.initialize(admin, ap, address(baseToken), FLAG_SLIPPAGE, hevm);
        EPOCH_FREQUENCY = EpochFrequency.DAILY;
        vault = MockedVault(EchidnaVaultUtils.createVault(address(baseToken), admin, SIDE_TOKEN_DECIMALS, ap, EPOCH_FREQUENCY, hevm));

        EchidnaVaultUtils.grantAdminRole(admin, address(vault));
        EchidnaVaultUtils.registerVault(admin, address(vault), ap, hevm);
        address sideToken = vault.sideToken();

        ig = MockedIG(EchidnaVaultUtils.igSetup(admin, vault, ap, hevm));
        hevm.prank(admin);
        ig.setUseOracleImpliedVolatility(USE_ORACLE_IMPL_VOL);

        MarketOracle marketOracle = MarketOracle(ap.marketOracle());
        uint256 frequency = ig.getEpoch().frequency;
        hevm.prank(admin);
        marketOracle.setDelay(address(baseToken), sideToken, frequency, 0, true);

        _impliedVolSetup(address(baseToken), sideToken, ap);
    }

    function skipTo(uint256 to) internal {
        hevm.warp(to);
    }

    function skipDay(bool additionalSecond) internal {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        hevm.warp(block.timestamp + 1 days + secondToAdd);
    }

    function skipWeek(bool additionalSecond) internal {
        uint256 secondToAdd = (additionalSecond) ? 1 : 0;
        hevm.warp(block.timestamp + 1 weeks + secondToAdd);
    }

    function _between(uint256 val, uint256 lower, uint256 upper) internal pure returns (uint256) {
        return lower + (val % (upper - lower + 1));
    }

    function _convertVm() internal view returns (Vm) {
        return Vm(address(hevm));
    }

    function _impliedVolSetup(address baseToken_, address sideToken, AddressProvider _ap) internal {
        MarketOracle apMarketOracle = MarketOracle(_ap.marketOracle());
        uint256 lastUpdate = apMarketOracle.getImpliedVolatilityLastUpdate(baseToken_, sideToken, EPOCH_FREQUENCY);
        if (lastUpdate == 0) {
            hevm.prank(admin);
            apMarketOracle.setImpliedVolatility(baseToken_, sideToken, EPOCH_FREQUENCY, VOLATILITY);
        }
    }
}
