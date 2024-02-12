// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FeeManager} from "@project/FeeManager.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";

abstract contract Parameters {
    bool internal FLAG_SLIPPAGE = false;
    bool internal USE_ORACLE_IMPL_VOL = false;

    // Vault parameters
    uint256 internal INITIAL_VAULT_DEPOSIT = 1_000_000_000e18;
    uint256 internal MIN_VAULT_DEPOSIT = 200_000;
    uint256 internal MAX_VAULT_DEPOSIT = 1_000_000_000e18;
    uint256 internal EPOCH_FREQUENCY = EpochFrequency.DAILY;

    // Token parameters
    uint8 internal BASE_TOKEN_DECIMALS = 18;
    uint8 internal SIDE_TOKEN_DECIMALS = 18;
    bool internal TOKEN_PRICE_CAN_CHANGE = true;
    uint256 internal MIN_TOKEN_PRICE = 0.01e18;
    uint256 internal MAX_TOKEN_PRICE = 1_000e18;

    // IG parameters
    uint256 internal VOLATILITY = 0.5e18;
    uint256 internal MIN_OPTION_BUY = 10_000; // MAX is bullAvailNotional or bearAvailNotional
    uint256 internal ACCEPTED_SLIPPAGE = 0.03e18;

    uint256 internal MIN_TIME_WARP = 1000; // see invariant IG_24_3

    // FEE MANAGER
    FeeManager.FeeParams internal FEE_PARAMS =
        FeeManager.FeeParams({
            timeToExpiryThreshold: 3600,
            minFeeBeforeTimeThreshold: 0,
            minFeeAfterTimeThreshold: 0,
            successFeeTier: 0,
            feePercentage: 0.0035e18,
            capPercentage: 0.125e18,
            maturityFeePercentage: 0.0015e18,
            maturityCapPercentage: 0.125e18
        });
}
