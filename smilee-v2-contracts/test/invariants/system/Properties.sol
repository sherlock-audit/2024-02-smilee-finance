// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {console} from "forge-std/console.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {PropertiesDescriptions} from "./PropertiesDescriptions.sol";
import {IPriceOracle} from "@project/interfaces/IPriceOracle.sol";
import {AmountsMath} from "@project/lib/AmountsMath.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EchidnaVaultUtils} from "../lib/EchidnaVaultUtils.sol";

abstract contract Properties is BeforeAfter, PropertiesDescriptions {
    error PropertyFail(string);

    struct DepositInfo {
        address user;
        uint256 amount;
        uint256 epoch;
    }

    struct BuyInfo {
        address recipient;
        uint256 epoch;
        uint256 epochCounter;
        uint256 amountUp;
        uint256 amountDown;
        uint256 strike;
        uint256 premium;
        uint256 utilizationRate;
        uint256 buyTokenPrice;
        uint256 expectedPremium;
        uint8 buyType;
        uint256 sigma;
        uint256 timestamp;
    }

    struct WithdrawInfo {
        address user;
        uint256 amount;
        uint256 epochCounter;
    }

    struct EpochInfo {
        uint256 epochTimestamp;
        uint256 epochStrike;
    }

    uint8 internal constant _BULL = 0;
    uint8 internal constant _BEAR = 1;
    uint8 internal constant _SMILEE = 2;

    uint8 internal constant _BUY = 0;
    uint8 internal constant _SELL = 1;

    // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);

    // Errors
    bytes32 internal constant _ERR_VAULT_DEAD = keccak256(abi.encodeWithSignature("VaultDead()"));
    bytes32 internal constant _ERR_VAULT_PAUSED = keccak256(abi.encodeWithSignature("Pausable: paused"));
    bytes32 internal constant _ERR_EPOCH_NOT_FINISHED = keccak256(abi.encodeWithSignature("EpochNotFinished()"));
    bytes32 internal constant _ERR_EXCEEDS_AVAILABLE = keccak256(abi.encodeWithSignature("ExceedsAvailable()"));
    bytes32 internal constant _ERR_PRICE_ZERO = keccak256(abi.encodeWithSignature("PriceZero()"));
    bytes32 internal constant _ERR_NOT_ENOUGH_NOTIONAL = keccak256(abi.encodeWithSignature("NotEnoughNotional()"));

    bytes4 internal constant _INSUFFICIENT_LIQUIDITY_SEL = bytes4(keccak256("InsufficientLiquidity(bytes4)"));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_01 = keccak256(abi.encodeWithSelector(_INSUFFICIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::lockedLiquidity <= _state.liquidity.newPendingPayoffs"))));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_02 = keccak256(abi.encodeWithSelector(_INSUFFICIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::sharePrice == 0"))));
    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_ROLL_03 = keccak256(abi.encodeWithSelector(_INSUFFICIENT_LIQUIDITY_SEL, bytes4(keccak256("_beforeRollEpoch()::_state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs - baseTokens"))));

    bytes32 internal constant _ERR_INSUFF_LIQUIDITY_EDGE_01 = keccak256(abi.encodeWithSelector(_INSUFFICIENT_LIQUIDITY_SEL, bytes4(keccak256("_sellSideTokens()"))));
    // bytes32 internal constant _ERR_INSUFF_LIQUIDITY_EDGE_02 = keccak256(abi.encodeWithSelector(_INSUFFICIENT_LIQUIDITY_SEL, bytes4(keccak256("_buySideTokens()")))); // Replace by InsufficientInput()
    bytes32 internal constant _ERR_INSUFFICIENT_INPUT = keccak256(abi.encodeWithSignature("InsufficientInput()")); // see TestnetSwapAdapter
    bytes32 internal constant _ERR_CHECK_SLIPPAGE = keccak256(abi.encodeWithSignature("SlippedMarketValue()")); // see test_21

    // Accept reverts array
    mapping(string => mapping(bytes32 => bool)) internal _ACCEPTED_REVERTS;

    function _initializeProperties() internal {
        // GENERAL 1 - No reverts allowed

        // GENERAL 5
        _ACCEPTED_REVERTS[_GENERAL_4.code][_ERR_INSUFF_LIQUIDITY_ROLL_01] = true;
        _ACCEPTED_REVERTS[_GENERAL_4.code][_ERR_INSUFF_LIQUIDITY_ROLL_02] = true;
        _ACCEPTED_REVERTS[_GENERAL_4.code][_ERR_INSUFF_LIQUIDITY_ROLL_03] = true;
        _ACCEPTED_REVERTS[_GENERAL_5.code][_ERR_EPOCH_NOT_FINISHED] = true;

        // GENERAL 6
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_NOT_ENOUGH_NOTIONAL] = true; // buy never more than notional available
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_EXCEEDS_AVAILABLE] = true; // sell never more than owned
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_INSUFFICIENT_INPUT] = true; // delta hedge can't be performed
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_PRICE_ZERO] = true; // option price is 0
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_INSUFF_LIQUIDITY_EDGE_01] = true; // delta hedge can't be performed
        _ACCEPTED_REVERTS[_GENERAL_6.code][_ERR_CHECK_SLIPPAGE] = true;
    }

    /// @notice Share price never goes to 0
    function smilee_invariants_vault_16() public view returns (bool) {
        if (vault.v0() > 0) {
            uint256 epochSharePrice = vault.epochPricePerShare(ig.getEpoch().previous);
            return epochSharePrice > 0;
        }
        return true;
    }

    function smilee_invariants_ig_20() public view returns (bool) {
        // uint256 price = IPriceOracle(ap.priceOracle()).getPrice(sideToken, address(baseToken));
        uint256 price = IPriceOracle(ap.priceOracle()).getPrice(ig.sideToken(), ig.baseToken());
        FeeManager feeManager = FeeManager(ap.feeManager());
        (, , uint256 minFeeAfterTimeThreshold, , , , , ) = feeManager.dvpsFeeParams(address(ig));
        return price >= 0 + minFeeAfterTimeThreshold;
    }

    function smilee_invariants_ig_25() public view returns (bool) {
        uint256 currentStrike = ig.currentStrike();
        (uint256 expectedPremiumSmilee, ) = ig.premium(currentStrike, 100e18, 100e18);
        (uint256 expectedPremiumBull, ) = ig.premium(currentStrike, 100e18, 0);
        (uint256 expectedPremiumBear, ) = ig.premium(currentStrike, 0, 100e18);
        return expectedPremiumSmilee == expectedPremiumBull + expectedPremiumBear;
    }

    function smilee_invariants_vault_9() public view returns (bool) {
        // uint256 price = IPriceOracle(ap.priceOracle()).getPrice(sideToken, address(baseToken));
        uint256 v0 = AmountsMath.wrapDecimals(vault.v0(), 18);
        uint256 price = IPriceOracle(ap.priceOracle()).getPrice(ig.sideToken(), ig.baseToken());
        uint256 k = ig.currentStrike();
        uint256 stv = ud(v0).div(convert(2).mul(ud(k))).mul(ud(price)).unwrap();
        uint256 btv = v0 / 2;
        return stv < btv ? v0 >= stv : v0 >= btv;
    }

    function smilee_invariants_vault_24() public view returns (bool) {
        uint256 notional = vault.notional();
        uint256 baseTokenAmount = IERC20(baseToken).balanceOf(address(vault));
        uint256 sideTokenValue = EchidnaVaultUtils.getSideTokenValue(vault, ap);
        return notional == baseTokenAmount + sideTokenValue; // TODO: ~

    }
}
