// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {IFeeManager} from "../../src/interfaces/IFeeManager.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Amount} from "../../src/lib/Amount.sol";
import {AmountsMath} from "../../src/lib/AmountsMath.sol";
import {FinanceParameters} from "../../src/lib/FinanceIG.sol";
import {Notional} from "../../src/lib/Notional.sol";
import {OptionStrategy} from "../../src/lib/OptionStrategy.sol";
import {Position} from "../../src/lib/Position.sol";
import {SignedMath} from "../../src/lib/SignedMath.sol";
import {TimeLock, TimeLockedUInt, TimeLockedBool} from "../../src/lib/TimeLock.sol";
import {IG} from "../../src/IG.sol";
import {Epoch, EpochController} from "../../src/lib/EpochController.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

//ToDo: Add comments
contract MockedIG is IG {
    using AmountsMath for uint256;
    using Notional for Notional.Info;
    using EpochController for Epoch;
    using TimeLock for TimeLockedUInt;
    using TimeLock for TimeLockedBool;

    bool internal _fakePremium;
    bool internal _fakePayoff;

    bool internal _fakeDeltaHedge;

    uint256 internal _optionPrice; // expressed in basis point (1% := 100)
    uint256 internal _payoffPercentage; // expressed in basis point (1% := 100)

    error OutOfAllowedRange();

    constructor(address vault_, address addressProvider_) IG(vault_, addressProvider_) {}

    function setOptionPrice(uint256 value) public {
        _optionPrice = value;
        _fakePremium = true;
    }

    function setPayoffPerc(uint256 value) public {
        _payoffPercentage = value;
        _fakePayoff = true;
    }

    function useRealPremium() public {
        _fakePremium = false;
    }

    function useFakeDeltaHedge() public {
        _fakeDeltaHedge = true;
    }

    function useRealDeltaHedge() public {
        _fakeDeltaHedge = false;
    }

    function useRealPercentage() public {
        _fakePayoff = false;
    }

    function premium(
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) public view override returns (uint256, uint256) {
        if (_fakePremium) {
            uint256 premium_ = ((amountUp + amountDown) * _optionPrice) / 10000;
            (uint256 fee, ) = IFeeManager(_getFeeManager()).tradeBuyFee(
                address(this),
                getEpoch().current,
                amountUp + amountDown,
                premium_,
                _baseTokenDecimals
            );
            return (premium_ + fee, fee);
        }
        return super.premium(strike, amountUp, amountDown);
    }

    function _getMarketValue(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy,
        uint256 swapPrice
    ) internal view virtual override returns (uint256) {
        if (_fakePremium || _fakePayoff) {
            // ToDo: review
            uint256 amountAbs = amount.up + amount.down;
            if (_fakePremium) {
                return (amountAbs * _optionPrice) / 10000;
            }
            if (_fakePayoff) {
                return amountAbs * _payoffPercentage;
            }
        }

        return super._getMarketValue(strike, amount, tradeIsBuy, swapPrice);
    }

    function _residualPayoffPerc(
        uint256 strike,
        uint256 price
    ) internal view virtual override returns (uint256 percentageCall, uint256 percentagePut) {
        if (_fakePayoff) {
            return (_payoffPercentage, _payoffPercentage);
        }
        return super._residualPayoffPerc(strike, price);
    }

    function _deltaHedgePosition(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy
    ) internal override returns (uint256 swapPrice) {
        if (_fakeDeltaHedge) {
            IVault(vault).deltaHedge(-int256((amount.up + amount.down) / 4));
            return 1e18;
        }
        swapPrice = super._deltaHedgePosition(strike, amount, tradeIsBuy);
    }

    // ToDo: review usage
    function positions(
        bytes32 positionID
    ) public view returns (uint256 amount, bool strategy, uint256 strike, uint256 epoch_) {
        Position.Info storage position = _epochPositions[getEpoch().current][positionID];
        strategy = (position.amountUp > 0) ? OptionStrategy.CALL : OptionStrategy.PUT;
        amount = (strategy) ? position.amountUp : position.amountDown;

        return (amount, strategy, position.strike, position.epoch);
    }

    function getCurrentFinanceParameters() public view returns (FinanceParameters memory) {
        return financeParameters;
    }

    /**
        @notice Get number of past and current epochs
        @return number The number of past and current epochs
     */
    function getNumberOfEpochs() external view returns (uint256 number) {
        number = getEpoch().numberOfRolledEpochs;
    }

    /**
        @dev Second last timestamp
     */
    function lastRolledEpoch() public view returns (uint256 lastEpoch) {
        lastEpoch = getEpoch().previous;
    }

    function currentEpoch() external view returns (uint256) {
        return getEpoch().current;
    }

    /// @dev must be defined in Wad
    function setSigmaMultiplier(uint256 value) external {
        _checkRole(ROLE_ADMIN);

        // TBD: review
        financeParameters.timeLocked.sigmaMultiplier.set(value, 0);
    }

    /// @dev must be defined in Wad
    function setTradeVolatilityUtilizationRateFactor(uint256 value) external {
        _checkRole(ROLE_ADMIN);
        if (value < 1e18 || value > 5e18) {
            revert OutOfAllowedRange();
        }

        // TBD: review
        financeParameters.timeLocked.tradeVolatilityUtilizationRateFactor.set(value, 0);
    }

    /// @dev must be defined in Wad
    function setTradeVolatilityTimeDecay(uint256 value) external {
        _checkRole(ROLE_ADMIN);
        if (value > 0.5e18) {
            revert OutOfAllowedRange();
        }

        // TBD: review
        financeParameters.timeLocked.tradeVolatilityTimeDecay.set(value, 0);
    }

    function setUseOracleImpliedVolatility(bool value) external {
        _checkRole(ROLE_ADMIN);

        // TBD: review
        financeParameters.timeLocked.useOracleImpliedVolatility.set(value, 0);
    }
}
