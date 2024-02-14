// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDVP} from "./interfaces/IDVP.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IVaultParams} from "./interfaces/IVaultParams.sol";
import {AmountsMath} from "./lib/AmountsMath.sol";
import {TimeLock, TimeLockedUInt} from "./lib/TimeLock.sol";

contract FeeManager is IFeeManager, AccessControl {
    using AmountsMath for uint256;
    using SafeERC20 for IERC20Metadata;
    using TimeLock for TimeLockedUInt;

    struct FeeParams {
        // Seconds remaining until the next epoch to determine which minFee to use.
        uint256 timeToExpiryThreshold;
        // Minimum amount of fee paid for any buy trade made before the threshold time (denominated in token decimals of the token used to pay the fee).
        uint256 minFeeBeforeTimeThreshold;
        // Minimum amount of fee paid for any buy trade made after the threshold time  (denominated in token decimals of the token used to pay the fee).
        uint256 minFeeAfterTimeThreshold;
        // Percentage to be appied to the PNL of the sell.
        uint256 successFeeTier;
        // Fee percentage applied for each DVPs in WAD, it's used to calculate fees on notional.
        uint256 feePercentage;
        // CAP percentage, works like feePercentage in WAD, but it's used to calculate fees on premium.
        uint256 capPercentage;
        // Fee percentage applied for each DVPs in WAD after maturity, it's used to calculate fees on notional.
        uint256 maturityFeePercentage;
        // CAP percentage, works like feePercentage in WAD after maturity, but it's used to calculate fees on premium.
        uint256 maturityCapPercentage;
    }

    struct TimeLockedFeeParams {
        // Seconds remaining until the next epoch to determine which minFee to use.
        TimeLockedUInt timeToExpiryThreshold;
        // Minimum amount of fee paid for any buy trade made before the threshold time (denominated in token decimals of the token used to pay the fee).
        TimeLockedUInt minFeeBeforeTimeThreshold;
        // Minimum amount of fee paid for any buy trade made after the threshold time  (denominated in token decimals of the token used to pay the fee).
        TimeLockedUInt minFeeAfterTimeThreshold;
        // Percentage to be appied to the PNL of the sell.
        TimeLockedUInt successFeeTier;
        // Fee percentage applied for each DVPs in WAD, it's used to calculate fees on notional.
        TimeLockedUInt feePercentage;
        // CAP percentage, works like feePercentage in WAD, but it's used to calculate fees on premium.
        TimeLockedUInt capPercentage;
        // Fee percentage applied for each DVPs in WAD after maturity, it's used to calculate fees on notional.
        TimeLockedUInt maturityFeePercentage;
        // CAP percentage, works like feePercentage in WAD after maturity, but it's used to calculate fees on premium.
        TimeLockedUInt maturityCapPercentage;
    }

    /// @notice Fee for each dvp
    mapping(address => TimeLockedFeeParams) internal _dvpsFeeParams;

    /// @notice Fee account per sender
    mapping(address => uint256) public senders;

    /// @notice Fee account per vault
    mapping(address => uint256) public vaultFeeAmounts;

    /// @notice Timelock delay for changing the parameters of a DVP
    uint256 public immutable timeLockDelay;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    event UpdateTimeToExpiryThreshold(address dvp, uint256 timeToExpiryThreshold, uint256 previous);
    event UpdateMinFeeBeforeTimeThreshold(address dvp, uint256 minFeeBeforeTimeThreshold, uint256 previous);
    event UpdateMinFeeAfterTimeThreshold(address dvp, uint256 minFeeAfterTimeThreshold, uint256 previous);
    event UpdateSuccessFeeTier(address dvp, uint256 minFeeAfterTimeThreshold, uint256 previous);
    event UpdateFeePercentage(address dvp, uint256 fee, uint256 previous);
    event UpdateCapPercentage(address dvp, uint256 fee, uint256 previous);
    event UpdateMaturityFeePercentage(address dvp, uint256 fee, uint256 previous);
    event UpdateMaturityCapPercentage(address dvp, uint256 fee, uint256 previous);
    event ReceiveFee(address sender, uint256 amount);
    event WithdrawFee(address receiver, address sender, uint256 amount);
    event TransferVaultFee(address vault, uint256 feeAmount);

    error NoEnoughFundsFromSender();
    error OutOfAllowedRange();
    error WrongVault();

    constructor(uint256 timeLockDelay_) AccessControl() {
        timeLockDelay = timeLockDelay_;

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    function dvpsFeeParams(address dvp) external view returns (
        uint256 timeToExpiryThreshold,
        uint256 minFeeBeforeTimeThreshold,
        uint256 minFeeAfterTimeThreshold,
        uint256 successFeeTier,
        uint256 feePercentage,
        uint256 capPercentage,
        uint256 maturityFeePercentage,
        uint256 maturityCapPercentage
    ) {
        timeToExpiryThreshold = _dvpsFeeParams[dvp].timeToExpiryThreshold.get();
        minFeeBeforeTimeThreshold = _dvpsFeeParams[dvp].minFeeBeforeTimeThreshold.get();
        minFeeAfterTimeThreshold = _dvpsFeeParams[dvp].minFeeAfterTimeThreshold.get();
        successFeeTier = _dvpsFeeParams[dvp].successFeeTier.get();
        feePercentage = _dvpsFeeParams[dvp].feePercentage.get();
        capPercentage = _dvpsFeeParams[dvp].capPercentage.get();
        maturityFeePercentage = _dvpsFeeParams[dvp].maturityFeePercentage.get();
        maturityCapPercentage = _dvpsFeeParams[dvp].maturityCapPercentage.get();
    }

    /**
        Set fee params for the given dvp.
        @param dvp The address of the DVP
        @param params The Fee Params to be set
     */
    function setDVPFee(address dvp, FeeParams calldata params) external {
        _checkRole(ROLE_ADMIN);

        _setTimeToExpiryThreshold(dvp, params.timeToExpiryThreshold);
        _setMinFeeBeforeTimeThreshold(dvp, params.minFeeBeforeTimeThreshold);
        _setMinFeeAfterTimeThreshold(dvp, params.minFeeAfterTimeThreshold);
        _setSuccessFeeTier(dvp, params.successFeeTier);
        _setFeePercentage(dvp, params.feePercentage);
        _setCapPercentage(dvp, params.capPercentage);
        _setMaturityFeePercentage(dvp, params.maturityFeePercentage);
        _setMaturityCapPercentage(dvp, params.maturityCapPercentage);
    }

    /// @inheritdoc IFeeManager
    function tradeBuyFee(
        address dvp,
        uint256 expiry,
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals
    ) external view returns (uint256 fee, uint256 minFee) {
        minFee = _minFee(dvp, expiry);
        fee = minFee + _getFeeFromNotionalAndPremium(dvp, notional, premium, tokenDecimals, false);
    }

    /// @inheritdoc IFeeManager
    function tradeSellFee(
        address dvp,
        uint256 expiry,
        uint256 notional,
        uint256 currPremium,
        uint256 entryPremium,
        uint8 tokenDecimals
    ) external view returns (uint256 fee, uint256 minFee) {
        fee = _getFeeFromNotionalAndPremium(dvp, notional, currPremium, tokenDecimals, block.timestamp > expiry);

        if (currPremium > entryPremium) {
            uint256 pnl = currPremium - entryPremium;
            pnl = AmountsMath.wrapDecimals(pnl, tokenDecimals);
            uint256 successFee = pnl.wmul(_dvpsFeeParams[dvp].successFeeTier.get());
            successFee = AmountsMath.unwrapDecimals(successFee, tokenDecimals);

            fee += successFee;
        }

        minFee = _minFee(dvp, expiry);
        fee += minFee;
    }

    /**
        @notice Gives minimum fee given current remaining time to expiry
        @param dvp Address of the DVP
        @param expiry current expiry timestamp of th egiven DVP
     */
    function _minFee(address dvp, uint256 expiry) internal view returns (uint256) {
        if (block.timestamp > expiry) {
            return 0;
        }
        return
            expiry - block.timestamp > _dvpsFeeParams[dvp].timeToExpiryThreshold.get()
                ? _dvpsFeeParams[dvp].minFeeBeforeTimeThreshold.get()
                : _dvpsFeeParams[dvp].minFeeAfterTimeThreshold.get();
    }

    function _getFeeFromNotionalAndPremium(
        address dvp,
        uint256 notional,
        uint256 premium,
        uint8 tokenDecimals,
        bool expired
    ) internal view returns (uint256 fee) {
        uint256 feeFromNotional;
        uint256 feeFromPremiumCap;
        notional = AmountsMath.wrapDecimals(notional, tokenDecimals);
        premium = AmountsMath.wrapDecimals(premium, tokenDecimals);

        if (expired) {
            feeFromNotional = notional.wmul(_dvpsFeeParams[dvp].maturityFeePercentage.get());
            feeFromPremiumCap = premium.wmul(_dvpsFeeParams[dvp].maturityCapPercentage.get());
        } else {
            feeFromNotional = notional.wmul(_dvpsFeeParams[dvp].feePercentage.get());
            feeFromPremiumCap = premium.wmul(_dvpsFeeParams[dvp].capPercentage.get());
        }

        fee = (feeFromNotional < feeFromPremiumCap) ? feeFromNotional : feeFromPremiumCap;
        fee = AmountsMath.unwrapDecimals(fee, tokenDecimals);
    }

    /// @inheritdoc IFeeManager
    function receiveFee(uint256 feeAmount) external {
        _getBaseTokenInfo(msg.sender).safeTransferFrom(msg.sender, address(this), feeAmount);
        senders[msg.sender] += feeAmount;

        emit ReceiveFee(msg.sender, feeAmount);
    }

    /// @inheritdoc IFeeManager
    function trackVaultFee(address vault, uint256 feeAmount) external {
        // Check sender:
        IDVP dvp = IDVP(msg.sender);
        if (vault != dvp.vault()) {
            revert WrongVault();
        }

        vaultFeeAmounts[vault] += feeAmount;

        emit TransferVaultFee(vault, feeAmount);
    }

    /// @inheritdoc IFeeManager
    function withdrawFee(address receiver, address sender, uint256 feeAmount) external {
        _checkRole(ROLE_ADMIN);
        if (senders[sender] < feeAmount) {
            revert NoEnoughFundsFromSender();
        }

        senders[sender] -= feeAmount;
        _getBaseTokenInfo(sender).safeTransfer(receiver, feeAmount);

        emit WithdrawFee(receiver, sender, feeAmount);
    }

    /// @notice Update time to expiry threshold value
    function _setTimeToExpiryThreshold(address dvp, uint256 timeToExpiryThreshold) internal {
        if (timeToExpiryThreshold == 0) {
            // TODO: review
            revert OutOfAllowedRange();
        }

        uint256 previousTimeToExpiryThreshold = _dvpsFeeParams[dvp].timeToExpiryThreshold.proposed;
        _dvpsFeeParams[dvp].timeToExpiryThreshold.set(timeToExpiryThreshold, timeLockDelay);

        emit UpdateTimeToExpiryThreshold(dvp, timeToExpiryThreshold, previousTimeToExpiryThreshold);
    }

    /// @notice Update fee percentage value
    function _setMinFeeBeforeTimeThreshold(address dvp, uint256 minFee) internal {
        uint8 tokenDecimals = _getBaseTokenInfo(dvp).decimals();
        if (minFee > 100 * 10 ** tokenDecimals) {
            revert OutOfAllowedRange();
        }

        uint256 previousMinFee = _dvpsFeeParams[dvp].minFeeBeforeTimeThreshold.proposed;
        _dvpsFeeParams[dvp].minFeeBeforeTimeThreshold.set(minFee, timeLockDelay);

        emit UpdateMinFeeBeforeTimeThreshold(dvp, minFee, previousMinFee);
    }

    /// @notice Update fee percentage value
    function _setMinFeeAfterTimeThreshold(address dvp, uint256 minFee) internal {
        uint8 tokenDecimals = _getBaseTokenInfo(dvp).decimals();
        if (minFee > 100 * 10 ** tokenDecimals) {
            revert OutOfAllowedRange();
        }

        uint256 previousMinFee = _dvpsFeeParams[dvp].minFeeAfterTimeThreshold.proposed;
        _dvpsFeeParams[dvp].minFeeAfterTimeThreshold.set(minFee, timeLockDelay);

        emit UpdateMinFeeAfterTimeThreshold(dvp, minFee, previousMinFee);
    }

    /// @notice Update fee percentage value
    function _setSuccessFeeTier(address dvp, uint256 successFeeTier) internal {
        if (successFeeTier > 1e18) {
            revert OutOfAllowedRange();
        }

        uint256 previousSuccessFeeTier = _dvpsFeeParams[dvp].successFeeTier.proposed;
        _dvpsFeeParams[dvp].successFeeTier.set(successFeeTier, timeLockDelay);

        emit UpdateSuccessFeeTier(dvp, successFeeTier, previousSuccessFeeTier);
    }

    /// @notice Update fee percentage value
    function _setFeePercentage(address dvp, uint256 feePercentage_) internal {
        if (feePercentage_ > 0.5e18) {
            revert OutOfAllowedRange();
        }

        uint256 previousFeePercentage = _dvpsFeeParams[dvp].feePercentage.proposed;
        _dvpsFeeParams[dvp].feePercentage.set(feePercentage_, timeLockDelay);

        emit UpdateFeePercentage(dvp, feePercentage_, previousFeePercentage);
    }

    /// @notice Update cap percentage value
    function _setCapPercentage(address dvp, uint256 capPercentage_) internal {
        if (capPercentage_ > 0.5e18) {
            revert OutOfAllowedRange();
        }

        uint256 previousCapPercentage = _dvpsFeeParams[dvp].capPercentage.proposed;
        _dvpsFeeParams[dvp].capPercentage.set(capPercentage_, timeLockDelay);

        emit UpdateCapPercentage(dvp, capPercentage_, previousCapPercentage);
    }

    /// @notice Update fee percentage value at maturity
    function _setMaturityFeePercentage(address dvp, uint256 maturityFeePercentage_) internal {
        if (maturityFeePercentage_ > 0.5e18) {
            revert OutOfAllowedRange();
        }

        uint256 previousMaturityFeePercentage = _dvpsFeeParams[dvp].maturityFeePercentage.proposed;
        _dvpsFeeParams[dvp].maturityFeePercentage.set(maturityFeePercentage_, timeLockDelay);

        emit UpdateMaturityFeePercentage(dvp, maturityFeePercentage_, previousMaturityFeePercentage);
    }

    /// @notice Update cap percentage value at maturity
    function _setMaturityCapPercentage(address dvp, uint256 maturityCapPercentage_) internal {
        if (maturityCapPercentage_ > 0.5e18) {
            revert OutOfAllowedRange();
        }

        uint256 previousMaturityCapPercentage = _dvpsFeeParams[dvp].maturityCapPercentage.proposed;
        _dvpsFeeParams[dvp].maturityCapPercentage.set(maturityCapPercentage_, timeLockDelay);

        emit UpdateMaturityCapPercentage(dvp, maturityCapPercentage_, previousMaturityCapPercentage);
    }

    /// @dev Get IERC20Metadata of baseToken of given sender
    function _getBaseTokenInfo(address sender) internal view returns (IERC20Metadata token) {
        token = IERC20Metadata(IVaultParams(sender).baseToken());
    }
}
