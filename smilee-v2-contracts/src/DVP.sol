// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IAddressProvider} from "./interfaces/IAddressProvider.sol";
import {IDVP, IDVPImmutables} from "./interfaces/IDVP.sol";
import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Amount, AmountHelper} from "./lib/Amount.sol";
import {Epoch} from "./lib/EpochController.sol";
import {Finance} from "./lib/Finance.sol";
import {Notional} from "./lib/Notional.sol";
import {Position} from "./lib/Position.sol";
import {EpochControls} from "./EpochControls.sol";
import {VaultLib} from "./lib/VaultLib.sol";

abstract contract DVP is IDVP, EpochControls, AccessControl, Pausable {
    using AmountHelper for Amount;
    using Position for Position.Info;
    using Notional for Notional.Info;
    using SafeERC20 for IERC20Metadata;

    /// @inheritdoc IDVPImmutables
    address public immutable override baseToken;
    /// @inheritdoc IDVPImmutables
    address public immutable override sideToken;
    /// @inheritdoc IDVPImmutables
    bool public immutable override optionType;
    /// @inheritdoc IDVP
    address public immutable override vault;

    IAddressProvider internal immutable _addressProvider;
    uint8 internal immutable _baseTokenDecimals;
    uint8 internal immutable _sideTokenDecimals;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    bytes32 public constant ROLE_EPOCH_ROLLER = keccak256("ROLE_EPOCH_ROLLER");

    /**
        @notice liquidity for options indexed by epoch
        @dev mapping epoch -> Notional.Info
     */
    mapping(uint256 => Notional.Info) internal _liquidity;

    /**
        @notice Users positions
        @dev mapping epoch -> Position.getID(...) -> Position.Info
        @dev There is an index by epoch in order to further avoid collisions within the hash of the position ID.
     */
    mapping(uint256 => mapping(bytes32 => Position.Info)) internal _epochPositions;

    error NotEnoughNotional();
    error PositionNotFound();
    error CantBurnMoreThanMinted();
    error MissingMarketOracle();
    error MissingPriceOracle();
    error MissingFeeManager();
    error SlippedMarketValue();
    error PayoffTooLow();
    error VaultDead();
    error OnlyPositionManager();

    /**
        @notice Emitted when option is minted for a given position
        @param sender The address that minted the option
        @param owner The owner of the option
     */
    event Mint(address sender, address indexed owner);

    /**
        @notice Emitted when a position's option is destroyed
        @param owner The owner of the position that is being burnt
     */
    event Burn(address indexed owner);

    event ChangedPauseState(bool paused);

    constructor(
        address vault_,
        bool optionType_,
        address addressProvider_
    )
        EpochControls(IEpochControls(vault_).getEpoch().frequency, IEpochControls(vault_).getEpoch().firstEpochTimespan)
        AccessControl()
        Pausable()
    {
        optionType = optionType_;
        vault = vault_;
        IVault vaultCt = IVault(vault);
        baseToken = vaultCt.baseToken();
        sideToken = vaultCt.sideToken();
        _baseTokenDecimals = IERC20Metadata(baseToken).decimals();
        _sideTokenDecimals = IERC20Metadata(sideToken).decimals();
        _addressProvider = IAddressProvider(addressProvider_);

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);
        _setRoleAdmin(ROLE_EPOCH_ROLLER, ROLE_ADMIN);

        _grantRole(ROLE_GOD, msg.sender);
    }

    /**
        @notice Creates a new, or increases an existing, position
        @param recipient The wallet of the recipient for the position
        @param strike The strike of the position to mint
        @param amount The notional of the position to mint
        @param expectedPremium The expected premium, assumed to not consider fees, used to check against the actual premium, only known at the end of the trade
        @param maxSlippage The maximum slippage percentage accepted between the given expected premium and the actual one
        @return premium_ The actual paid premium
        @dev The client must approve the expected premium + slippage percentage, if actual premium will result in more than this quantity it will revert
     */
    function _mint(
        address recipient,
        uint256 strike,
        Amount memory amount,
        uint256 expectedPremium,
        uint256 maxSlippage
    ) internal returns (uint256 premium_) {
        _checkEpochNotFinished();
        _requireNotPaused();
        if (IVault(vault).dead()) {
            revert VaultDead();
        }
        if (amount.up == 0 && amount.down == 0) {
            revert AmountZero();
        }
        if ((amount.up > 0 && amount.down > 0) && (amount.up != amount.down)) {
            // If amount is an unbalanced smile, only the position manager is allowed to proceed:
            if (msg.sender != _addressProvider.dvpPositionManager()) {
                revert OnlyPositionManager();
            }
        }

        Epoch memory epoch = getEpoch();
        Notional.Info storage liquidity = _liquidity[epoch.current];

        // Check available liquidity:
        Amount memory availableLiquidity = liquidity.available(strike);
        if (availableLiquidity.up < amount.up || availableLiquidity.down < amount.down) {
            revert NotEnoughNotional();
        }

        {
            uint256 swapPrice = _deltaHedgePosition(strike, amount, true);
            uint256 premiumOrac = _getMarketValue(strike, amount, true, IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken));
            uint256 premiumSwap = _getMarketValue(strike, amount, true, swapPrice);
            premium_ = premiumSwap > premiumOrac ? premiumSwap : premiumOrac;
        }

        IFeeManager feeManager = IFeeManager(_getFeeManager());
        (uint256 fee, uint256 vaultFee) = feeManager.tradeBuyFee(
            address(this),
            epoch.current,
            amount.up + amount.down,
            premium_,
            _baseTokenDecimals
        );

        // Revert if actual price exceeds the previewed premium
        // NOTE: cannot use the approved premium as a reference due to the PositionManager...
        _checkSlippage(premium_ + fee, expectedPremium, maxSlippage, true);

        // Get fees from sender:
        IERC20Metadata(baseToken).safeTransferFrom(msg.sender, address(this), fee - vaultFee);
        IERC20Metadata(baseToken).safeApprove(address(feeManager), fee - vaultFee);
        feeManager.receiveFee(fee - vaultFee);

        // Get base premium from sender:
        IERC20Metadata(baseToken).safeTransferFrom(msg.sender, vault, premium_ + vaultFee);
        feeManager.trackVaultFee(address(vault), vaultFee);

        // Update user premium:
        premium_ += fee;

        // Decrease available liquidity:
        liquidity.increaseUsage(strike, amount);

        // Create or update position:
        Position.Info storage position = _getPosition(epoch.current, recipient, strike);
        position.premium += premium_;
        position.epoch = epoch.current;
        position.strike = strike;
        position.amountUp += amount.up;
        position.amountDown += amount.down;

        emit Mint(msg.sender, recipient);
    }

    function _checkSlippage(
        uint256 premium,
        uint256 expectedpremium,
        uint256 maxSlippage,
        bool tradeIsBuy
    ) internal pure {
        if (!Finance.checkSlippage(premium, expectedpremium, maxSlippage, tradeIsBuy)) {
            revert SlippedMarketValue();
        }
    }

    /**
        @notice It attempts to flat the DVP's delta by selling/buying an amount of side tokens in order to hedge the position.
        @notice By hedging the position, we avoid the impermanent loss.
        @param strike The position strike.
        @param amount The position notional.
        @param tradeIsBuy Positive if buyed by a user, negative otherwise.
     */
    function _deltaHedgePosition(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy
    ) internal virtual returns (uint256 swapPrice);

    /**
        @notice Burn or decrease a position.
        @param expiry The expiry timestamp of the position.
        @param recipient The wallet of the recipient for the opened position.
        @param strike The strike
        @param amount The notional.
        @param expectedMarketValue The expected market value when the epoch is the current one.
        @param maxSlippage The maximum slippage percentage.
        @return paidPayoff The paid payoff.
     */
    function _burn(
        uint256 expiry,
        address recipient,
        uint256 strike,
        Amount memory amount,
        uint256 expectedMarketValue,
        uint256 maxSlippage
    ) internal returns (uint256 paidPayoff) {
        _requireNotPaused();
        Position.Info storage position = _getPosition(expiry, msg.sender, strike);
        if (!position.exists()) {
            revert PositionNotFound();
        }

        // // If the position reached maturity, the user must close the entire position
        // // NOTE: we have to avoid this due to the PositionManager that holds positions for multiple tokens.
        // if (position.epoch != epoch.current) {
        //     amount = position.amount;
        // }
        if (amount.up == 0 && amount.down == 0) {
            // NOTE: a zero amount may have some parasite effect, henct we proactively protect against it.
            revert AmountZero();
        }
        if (amount.up > position.amountUp || amount.down > position.amountDown) {
            revert CantBurnMoreThanMinted();
        }
        if ((amount.up > 0 && amount.down > 0) && (amount.up != amount.down)) {
            // If amount is an unbalanced smile, only the position manager is allowed to proceed:
            if (msg.sender != _addressProvider.dvpPositionManager()) {
                revert OnlyPositionManager();
            }
        }

        bool expired = expiry != getEpoch().current;
        if (!expired) {
            // NOTE: checked only here as expired positions needs to be burned even if the vault was killed.
            _checkEpochNotFinished();

            uint256 swapPrice = _deltaHedgePosition(strike, amount, false);
            uint256 payoffOrac = _getMarketValue(strike, amount, false, IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken));
            uint256 payoffSwap = _getMarketValue(strike, amount, false, swapPrice);
            paidPayoff = payoffSwap < payoffOrac ? payoffSwap : payoffOrac;
            _checkSlippage(paidPayoff, expectedMarketValue, maxSlippage, false);
        } else {
            // Compute the payoff to be paid:
            Amount memory payoff_ = _liquidity[expiry].shareOfPayoff(strike, amount, _baseTokenDecimals);
            paidPayoff = payoff_.getTotal();

            // Account transfer of setted aside payoff:
            _liquidity[expiry].decreasePayoff(strike, payoff_);
        }

        // NOTE: premium fix for the leverage issue annotated in the mint flow.
        // notional : position.notional = fix : position.premium
        uint256 entryPremiumProp = ((amount.up + amount.down) * position.premium) /
            (position.amountUp + position.amountDown);
        position.premium -= entryPremiumProp;

        IFeeManager feeManager = IFeeManager(_getFeeManager());
        (uint256 fee, uint256 vaultFee) = feeManager.tradeSellFee(
            address(this),
            expiry,
            amount.up + amount.down,
            paidPayoff,
            entryPremiumProp,
            _baseTokenDecimals
        );

        if (paidPayoff >= fee) {
            paidPayoff -= fee;
        } else {
            // if the option didn't reached maturity, vaultFee is always paid expect if vaultFee exceed paidPayoff
            if (!expired && vaultFee > paidPayoff) {
                revert PayoffTooLow();
            }

            // Fee becomes all paidPayoff and the user will not receive anything.
            fee = paidPayoff;
            paidPayoff = 0;

            // if vaultFee is greater than the paidPayoff all the fee will be transfered to the Vault.
            if (vaultFee > fee) {
                vaultFee = fee;
            }
        }

        // Account change of used liquidity between wallet and protocol:
        position.amountUp -= amount.up;
        position.amountDown -= amount.down;
        // NOTE: must be updated after the previous computations based on used liquidity.
        _liquidity[expiry].decreaseUsage(strike, amount);

        uint256 netFee = fee - vaultFee;
        IVault(vault).transferPayoff(recipient, paidPayoff, expired);

        IVault(vault).transferPayoff(address(this), netFee, expired);
        IERC20Metadata(baseToken).safeApprove(address(feeManager), netFee);
        feeManager.receiveFee(netFee);
        feeManager.trackVaultFee(address(vault), vaultFee);

        emit Burn(msg.sender);
    }

    /// @inheritdoc EpochControls
    function _beforeRollEpoch() internal virtual override {
        _checkRole(ROLE_EPOCH_ROLLER);
        _requireNotPaused();

        // NOTE: avoids breaking computations when there is nothing to compute.
        //       This may break when the underlying vault has no liquidity (e.g. on the very first epoch).
        IVault vaultCt = IVault(vault);
        if (vaultCt.v0() > 0) {
            // Accounts the payoff for each strike and strategy of the positions in circulation that is still to be redeemed:
            _accountResidualPayoffs(IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken));
            // Reserve the payoff of those positions:
            uint256 payoffToReserve = _residualPayoff();
            vaultCt.reservePayoff(payoffToReserve);
        }

        IEpochControls(vault).rollEpoch();
    }

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        uint256 initialCapital = IVault(vault).v0();
        _allocateLiquidity(initialCapital);
    }

    /**
        @notice Setup initial notional for a new epoch
        @param initialCapital The initial notional
        @dev The concrete DVP must allocate the initial notional on the various strikes and strategies
     */
    function _allocateLiquidity(uint256 initialCapital) internal virtual;

    /**
        @notice Computes and stores the residual payoffs for each strike and strategy of the outstanding positions that have not been redeemed
        @param price The side token price used to compute the payoff
        @dev The concrete DVP must compute and account the payoff for the various strikes and strategies
     */
    function _accountResidualPayoffs(uint256 price) internal virtual;

    /**
        @notice Utility function to simplify the work done in _accountResidualPayoffs()
     */
    function _accountResidualPayoff(uint256 strike, uint256 price) internal {
        Notional.Info storage liquidity = _liquidity[getEpoch().current];

        // computes the payoff to be set aside at the end of the epoch for the provided strike.
        Amount memory residualAmount = liquidity.getUsed(strike);
        (uint256 percentageUp, uint256 percentageDown) = _residualPayoffPerc(strike, price);
        (uint256 payoffUp_, uint256 payoffDown_) = Finance.computeResidualPayoffs(
            residualAmount,
            percentageUp,
            percentageDown,
            _baseTokenDecimals
        );

        liquidity.accountPayoffs(strike, payoffUp_, payoffDown_);
    }

    /**
        @notice Returns the accounted payoff of the positions in circulation that is still to be redeemed.
        @return residualPayoff the overall payoff to be set aside for the closing epoch.
        @dev The concrete DVP must iterate on the various strikes and strategies.
     */
    function _residualPayoff() internal view virtual returns (uint256 residualPayoff);

    /**
        @notice Computes the payoff percentage (a scale factor) for the given strike at epoch end
        @param strike The reference strike
        @param price The underlying side token price to compute payoff
        @return percentageCall The payoff percentage
        @return percentagePut The payoff percentage
        @dev The percentage is expected to be defined in Wad (i.e. 100 % := 1e18)
     */
    function _residualPayoffPerc(
        uint256 strike,
        uint256 price
    ) internal view virtual returns (uint256 percentageCall, uint256 percentagePut);

    /// @dev computes the premium/payoff with the given amount, swap price and post-trade volatility
    function _getMarketValue(
        uint256 strike,
        Amount memory amount,
        bool tradeIsBuy,
        uint256 swapPrice
    ) internal view virtual returns (uint256);

    /// @inheritdoc IDVP
    function payoff(
        uint256 expiry,
        uint256 strike,
        uint256 amountUp,
        uint256 amountDown
    ) public view virtual returns (uint256 payoff_, uint256 fee_) {
        Position.Info storage position = _getPosition(expiry, msg.sender, strike);
        if (!position.exists()) {
            revert PositionNotFound();
        }

        Amount memory amount_ = Amount({up: amountUp, down: amountDown});
        bool expired = position.epoch != getEpoch().current;

        if (!expired) {
            // The user wants to know how much is her position worth before reaching maturity
            uint256 price = IPriceOracle(_getPriceOracle()).getPrice(sideToken, baseToken);
            payoff_ = _getMarketValue(strike, amount_, false, price);
        } else {
            // The position expired, the user must close the entire position

            // The position is eligible for a share of the <epoch, strike, strategy> payoff set aside at epoch end:

            Amount memory payoffAmount_ = _liquidity[position.epoch].shareOfPayoff(
                position.strike,
                amount_,
                _baseTokenDecimals
            );
            payoff_ = payoffAmount_.getTotal();
        }

        IFeeManager feeManager = IFeeManager(_getFeeManager());
        (fee_, ) = feeManager.tradeSellFee(
            address(this),
            expiry,
            amount_.up + amount_.down,
            payoff_,
            position.premium,
            _baseTokenDecimals
        );

        if (payoff_ >= fee_) {
            payoff_ -= fee_;
        } else {
            fee_ = payoff_;
            payoff_ = 0;
        }
    }

    /**
        @notice Lookups the requested position.
        @param epoch The epoch of the position.
        @param owner The owner of the position.
        @param strike The strike of the position.
        @return position_ The requested position.
        @dev The client should check if the position exists by calling `exists()` on it.
     */
    function _getPosition(
        uint256 epoch,
        address owner,
        uint256 strike
    ) internal view returns (Position.Info storage position_) {
        return _epochPositions[epoch][Position.getID(owner, strike)];
    }

    function _getMarketOracle() internal view returns (address marketOracle) {
        marketOracle = _addressProvider.marketOracle();

        if (marketOracle == address(0)) {
            revert MissingMarketOracle();
        }
    }

    function _getPriceOracle() internal view returns (address priceOracle) {
        priceOracle = _addressProvider.priceOracle();

        if (priceOracle == address(0)) {
            revert MissingPriceOracle();
        }
    }

    function _getFeeManager() internal view returns (address feeManager) {
        feeManager = _addressProvider.feeManager();

        if (feeManager == address(0)) {
            revert MissingFeeManager();
        }
    }

    /**
        @notice Pause/Unpause
     */
    function changePauseState() external {
        _checkRole(ROLE_ADMIN);

        bool paused = paused();

        if (paused) {
            _unpause();
        } else {
            _pause();
        }

        emit ChangedPauseState(!paused);
    }
}
