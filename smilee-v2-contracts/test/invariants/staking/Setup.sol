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
import {MasterChefSmilee} from "@project/periphery/MasterChefSmilee.sol";
import {MasterChefSmilee} from "@project/periphery/MasterChefSmilee.sol";
import {SimpleRewarderPerSec} from "@project/periphery/SimpleRewarderPerSec.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";
import {Parameters} from "../utils/Parameters.sol";

abstract contract Setup is Parameters{
    address internal constant VM_ADDRESS_SETUP = address(uint160(uint256(keccak256("hevm cheat code"))));
    IHevm internal hevm;

    address internal depositor = address(0xf9a);
    address internal admin = address(0xf9c);

    MockedVault internal vault;
    MasterChefSmilee internal mcs;
    SimpleRewarderPerSec internal rewarder;
    uint256 internal smileePerSec = 1;

    constructor() {
        hevm = IHevm(VM_ADDRESS_SETUP);

        BASE_TOKEN_DECIMALS = 6;
        SIDE_TOKEN_DECIMALS = 18;
        EPOCH_FREQUENCY = EpochFrequency.DAILY;
        USE_ORACLE_IMPL_VOL = false;
        FLAG_SLIPPAGE = false;
    }

    function deploy() internal {
        hevm.warp(EpochFrequency.REF_TS + 1);
        AddressProvider ap = new AddressProvider(0);
        ap.grantRole(ap.ROLE_ADMIN(), admin);

        TestnetToken baseToken = new TestnetToken("BaseTestToken", "BTT");
        baseToken.transferOwnership(admin);
        hevm.prank(admin);
        baseToken.setAddressProvider(address(ap));

        AddressProviderUtils.initialize(admin, ap, address(baseToken), false, hevm);
        vault = MockedVault(EchidnaVaultUtils.createVault(address(baseToken), admin, SIDE_TOKEN_DECIMALS, ap, EpochFrequency.DAILY, hevm));

        EchidnaVaultUtils.grantAdminRole(admin, address(vault));
        EchidnaVaultUtils.registerVault(admin, address(vault), ap, hevm);
        EchidnaVaultUtils.grantEpochRollerRole(admin, admin, address(vault), hevm);
        address sideToken = vault.sideToken();

        _impliedVolSetup(address(baseToken), sideToken, ap);

        skipDay(false);
        EchidnaVaultUtils.rollEpoch(admin, vault, hevm);

        VaultUtils.addVaultDeposit(depositor, INITIAL_VAULT_DEPOSIT, admin, address(vault), _convertVm());

        skipDay(false);
        EchidnaVaultUtils.rollEpoch(admin, vault, hevm);

        hevm.prank(depositor);
        vault.redeem(INITIAL_VAULT_DEPOSIT);

        mcs = new MasterChefSmilee(smileePerSec, block.timestamp, ap);

        skipDay(false);
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

    function _impliedVolSetup(address baseToken, address sideToken, AddressProvider ap) internal {
      MarketOracle apMarketOracle = MarketOracle(ap.marketOracle());
      uint256 lastUpdate = apMarketOracle.getImpliedVolatilityLastUpdate(baseToken, sideToken, EpochFrequency.DAILY);
      if (lastUpdate == 0) {
          hevm.prank(admin);
          apMarketOracle.setImpliedVolatility(baseToken, sideToken, EpochFrequency.DAILY, 0.5e18);
      }
    }
}
