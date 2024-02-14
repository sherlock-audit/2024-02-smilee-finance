// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAddressProvider} from "./interfaces/IAddressProvider.sol";
import {IExchange} from "./interfaces/IExchange.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVaultAccessNFT} from "./interfaces/IVaultAccessNFT.sol";
import {IVaultParams} from "./interfaces/IVaultParams.sol";
import {Epoch, EpochController} from "./lib/EpochController.sol";
import {TokensPair} from "./lib/TokensPair.sol";
import {VaultLib} from "./lib/VaultLib.sol";
import {EpochControls} from "./EpochControls.sol";

contract Vault is IVault, ERC20, EpochControls, AccessControl, Pausable {
    using VaultLib for VaultLib.DepositReceipt;
    using EpochController for Epoch;
    using SafeERC20 for IERC20;

    /// @inheritdoc IVaultParams
    address public immutable baseToken;

    /// @inheritdoc IVaultParams
    address public immutable sideToken;

    /// @notice The address of the DVP paired with this vault
    address public dvp; // NOTE: public for frontend purposes
    bool internal _dvpSet;

    /// @notice Maximum threshold for users cumulative deposit (see VaultLib.VaultState.liquidity.totalDeposit)
    uint256 public maxDeposit;

    uint8 internal immutable _shareDecimals;

    /// @inheritdoc IVault
    mapping(address => VaultLib.DepositReceipt) public depositReceipts;

    /// @inheritdoc IVault
    mapping(address => VaultLib.Withdrawal) public withdrawals;

    mapping(uint256 => uint256) public epochPricePerShare; // NOTE: public for frontend and historical data purposes

    VaultLib.VaultState internal _state;

    /// @notice The provider for external services addresses
    IAddressProvider internal immutable _addressProvider;

    /// @notice Flag to tell if this vault is currently bound to priority access for deposits
    bool public priorityAccessFlag;

    /// @notice Tolerance margin when buying side tokens exceeds the availability (in basis points [0 - 10000])
    uint256 internal _hedgeMargin;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");
    bytes32 public constant ROLE_EPOCH_ROLLER = keccak256("ROLE_EPOCH_ROLLER");

    error AddressZero();
    error AmountZero();
    error DVPAlreadySet();
    error DVPNotSet();
    error ExceedsAvailable(); // raised when a user tries to move more assets than allowed to or owned
    error ExceedsMaxDeposit();
    error ExistingIncompleteWithdraw();
    error OnlyDVPAllowed();
    error PriorityAccessDenied();
    error VaultDead();
    error VaultNotDead();
    error WithdrawNotInitiated();
    error WithdrawTooEarly();
    error InsufficientLiquidity(bytes4); // raise when accounting operations would break the system due to lack of liquidity
    error FailingDeltaHedge();

    event Deposit(uint256 amount);
    event Redeem(uint256 amount);
    event InitiateWithdraw(uint256 amount);
    event Withdraw(uint256 amount);
    // Used by TheGraph for frontend needs:
    event VaultTVL(uint256 epoch, uint256 value);
    event MissingLiquidity(uint256 missing);
    event ChangedHedgeMargin(uint256 basisPoints);
    event Killed();
    event ChangedPauseState(bool paused);
    error OutOfAllowedRange();

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_,
        uint256 firstEpochTimespan,
        address addressProvider_
    ) ERC20("Smilee Share", ":)") EpochControls(epochFrequency_, firstEpochTimespan) AccessControl() Pausable() {
        TokensPair.validate(TokensPair.Pair({baseToken: baseToken_, sideToken: sideToken_}));
        baseToken = baseToken_;
        sideToken = sideToken_;

        // Shares have the same number of decimals as the base token
        _shareDecimals = IERC20Metadata(baseToken).decimals();

        _addressProvider = IAddressProvider(addressProvider_);
        maxDeposit = 1_000_000_000 * (10 ** _shareDecimals);

        _hedgeMargin = 250; // 2.5 %
        priorityAccessFlag = false;
        _dvpSet = false;

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);
        _setRoleAdmin(ROLE_EPOCH_ROLLER, ROLE_ADMIN);

        _grantRole(ROLE_GOD, msg.sender);
    }

    function decimals() public view override returns (uint8) {
        return _shareDecimals;
    }

    modifier isNotDead() {
        if (_state.dead) {
            revert VaultDead();
        }
        _;
    }

    modifier isDead() {
        if (!_state.dead) {
            revert VaultNotDead();
        }
        _;
    }

    modifier onlyDVP() {
        if (!_dvpSet) {
            revert DVPNotSet();
        }
        if (msg.sender != dvp) {
            revert OnlyDVPAllowed();
        }
        _;
    }

    /**
        @notice Allows the contract's owner to set the DVP paired with this vault
        @dev The address is injected after-build, because the DVP needs an already built vault as constructor-injected dependency
     */
    function setAllowedDVP(address dvp_) external {
        _checkRole(ROLE_ADMIN);

        if (_dvpSet) {
            revert DVPAlreadySet();
        }

        dvp = dvp_;
        _dvpSet = true;

        _grantRole(ROLE_EPOCH_ROLLER, dvp_);
    }

    /**
        @notice Set the tolerated hedge margin
        @param hedgeMargin The number of basis points (10000 is 100%)
     */
    function setHedgeMargin(uint256 hedgeMargin) external {
        _checkRole(ROLE_ADMIN);
        // Cap is 10%
        if (hedgeMargin > 1000) {
            revert OutOfAllowedRange();
        }

        _hedgeMargin = hedgeMargin;

        emit ChangedHedgeMargin(hedgeMargin);
    }

    /**
        @notice Set maximum deposit capacity for the Vault
        @param maxDeposit_ The number of base tokens
     */
    function setMaxDeposit(uint256 maxDeposit_) external {
        _checkRole(ROLE_ADMIN);

        maxDeposit = maxDeposit_;
    }

    function killVault() external {
        _checkRole(ROLE_ADMIN);

        _state.killed = true;

        emit Killed();
    }

    function vaultState()
        external
        view
        returns (
            uint256 lockedLiquidityInitially,
            uint256 pendingDeposit,
            uint256 totalWithdrawAmount,
            uint256 pendingPayoffs,
            uint256 totalDeposit,
            uint256 queuedWithdrawShares,
            uint256 currentQueuedWithdrawShares,
            bool dead_,
            bool killed
        )
    {
        return (
            _state.liquidity.lockedInitially,
            _state.liquidity.pendingDeposits,
            _state.liquidity.pendingWithdrawals,
            _state.liquidity.pendingPayoffs,
            _state.liquidity.totalDeposit,
            _state.withdrawals.heldShares,
            _state.withdrawals.newHeldShares,
            _state.dead,
            _state.killed
        );
    }

    /// @inheritdoc IVault
    function balances() public view returns (uint256 baseTokenAmount, uint256 sideTokenAmount) {
        baseTokenAmount = _notionalBaseTokens();
        sideTokenAmount = _notionalSideTokens();
    }

    /**
        @notice Provides the total portfolio value in base tokens
        @return value The total portfolio value in base tokens
     */
    function notional() public view returns (uint256) {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        uint256 baseTokens = _notionalBaseTokens();
        uint256 sideTokens = _notionalSideTokens();
        uint256 valueOfSideTokens = exchange.getOutputAmount(sideToken, baseToken, sideTokens);

        return baseTokens + valueOfSideTokens;
    }

    /**
        @notice Provides the current amount of base tokens available for DVP operations in the current epoch.
        @return amount_ The current amount of available base tokens
        @dev In the current epoch, that amount is everything except the amounts putted aside.
     */
    function _notionalBaseTokens() internal view returns (uint256 amount_) {
        (uint256 baseTokens, ) = _tokenBalances();

        uint256 pendings = _state.liquidity.pendingWithdrawals +
            _state.liquidity.pendingDeposits +
            _state.liquidity.pendingPayoffs;

        // Just catching the underflow and reverting with a more explicit error (see [IL-NOTE])
        if (baseTokens < pendings) {
            revert InsufficientLiquidity(bytes4(keccak256("_notionalBaseTokens()")));
        }

        return baseTokens - pendings;
    }

    /**
        @notice Provides the amount of side tokens from the portfolio of the current epoch.
        @return amount_ The amount of side tokens
     */
    function _notionalSideTokens() internal view returns (uint256 amount_) {
        (, amount_) = _tokenBalances();
    }

    function _tokenBalances() internal view returns (uint256 baseTokens, uint256 sideTokens) {
        baseTokens = IERC20(baseToken).balanceOf(address(this));
        sideTokens = IERC20(sideToken).balanceOf(address(this));
    }

    /// @inheritdoc IVault
    function v0() public view virtual returns (uint256) {
        return _state.liquidity.lockedInitially;
    }

    /// @inheritdoc IVault
    function dead() external view returns (bool) {
        return _state.killed;
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

    /**
        @notice Allows the contract's owner to enable or disable the priority access to deposit operations
     */
    function setPriorityAccessFlag(bool flag) external {
        _checkRole(ROLE_ADMIN);

        priorityAccessFlag = flag;
    }

    // ------------------------------------------------------------------------
    // USER OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc IVault
    function deposit(uint256 amount, address receiver, uint256 accessTokenId) external isNotDead whenNotPaused {
        _checkEpochNotFinished();

        if (amount == 0) {
            revert AmountZero();
        }

        // Avoids underflows when the maxDeposit is setted below than the totalDeposit
        if (_state.liquidity.totalDeposit > maxDeposit) {
            revert ExceedsMaxDeposit();
        }

        if (amount > maxDeposit - _state.liquidity.totalDeposit) {
            revert ExceedsMaxDeposit();
        }

        _usePriorityAccess(amount, receiver, accessTokenId);

        _state.liquidity.pendingDeposits += amount;
        _state.liquidity.totalDeposit += amount;
        _emitUpdatedDepositReceipt(receiver, amount);

        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(amount);
    }

    /**
        @notice Create or update a deposit receipt for a given deposit operation.
        @param creditor The wallet of the creditor
        @param amount The deposited amount
        @dev The deposit receipt allows the creditor to redeem its shares or withdraw liquidity.
     */
    function _emitUpdatedDepositReceipt(address creditor, uint256 amount) internal {
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[creditor];
        Epoch memory epoch = getEpoch();

        // Get the number of unredeemed shares from previous deposits, if any.
        // NOTE: the amount of unredeemed shares is the one of the previous epochs, as we still don't know the share price.
        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            epoch.current,
            epochPricePerShare[depositReceipt.epoch],
            _shareDecimals
        );

        // If the user has already deposited in the current epoch, add the amount to the total one of the next epoch:
        if (epoch.current == depositReceipt.epoch) {
            depositReceipt.amount = depositReceipt.amount + amount;
        } else {
            depositReceipt.amount = amount;
        }

        depositReceipt.epoch = epoch.current;
        depositReceipt.cumulativeAmount = depositReceipt.cumulativeAmount + amount;
        depositReceipt.unredeemedShares = unredeemedShares;
    }

    /**
        @notice Get wallet balance of actual owned shares and owed shares.
        @return heldByAccount The amount of shares owned by the wallet
        @return heldByVault The amount of shares owed to the wallet
     */
    function shareBalances(address account) public view returns (uint256 heldByAccount, uint256 heldByVault) {
        VaultLib.DepositReceipt memory depositReceipt = depositReceipts[account];

        if (depositReceipt.epoch == 0) {
            return (0, 0);
        }

        heldByAccount = balanceOf(account);

        heldByVault = depositReceipt.getSharesFromReceipt(
            getEpoch().current,
            epochPricePerShare[depositReceipt.epoch],
            _shareDecimals
        );
    }

    /**
        @notice Redeems shares held by the vault for the calling wallet
        @param shares is the number of shares to redeem
     */
    function redeem(uint256 shares) external whenNotPaused {
        if (shares == 0) {
            revert AmountZero();
        }
        // NOTE: if the epoch has not been initialized, it reverts with ExceedsAvailable.
        _redeem(shares, false);
    }

    function _redeem(uint256 shares, bool isMax) internal {
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        Epoch memory epoch = getEpoch();

        uint256 unredeemedShares = depositReceipt.getSharesFromReceipt(
            epoch.current,
            epochPricePerShare[depositReceipt.epoch],
            _shareDecimals
        );

        if (!isMax && shares > unredeemedShares) {
            revert ExceedsAvailable();
        }

        if (isMax) {
            shares = unredeemedShares;
        }

        if (shares == 0) {
            return;
        }

        if (depositReceipt.epoch < epoch.current) {
            // NOTE: all the amount - if any - has already been converted in unredeemedShares.
            depositReceipt.amount = 0;
        }

        depositReceipt.unredeemedShares = unredeemedShares - shares;

        _transfer(address(this), msg.sender, shares);

        emit Redeem(shares);
    }

    /// @inheritdoc IVault
    function initiateWithdraw(uint256 shares) external whenNotPaused isNotDead {
        _checkEpochNotFinished();

        _initiateWithdraw(shares, false);
    }

    function _initiateWithdraw(uint256 shares, bool isMax) internal {
        // We take advantage of this flow in order to also transfer any unredeemed share to the user.
        _redeem(0, true);
        // NOTE: since we made a 'redeem all', from now on all the user's shares are owned by him.
        uint256 userShares = balanceOf(msg.sender);

        if (isMax) {
            shares = userShares;
        }

        if (shares == 0) {
            revert AmountZero();
        }

        if (shares > userShares) {
            revert ExceedsAvailable();
        }

        Epoch memory epoch = getEpoch();
        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        // If there is a pre-ordered withdrawal in the past, the user must first complete it.
        if (withdrawal.epoch < epoch.current && withdrawal.shares > 0) {
            revert ExistingIncompleteWithdraw();
        }

        // Update user withdrawal receipt:
        // NOTE: the withdrawal.shares value is zeroed when the user complete a withdraw.
        // NOTE: if there is a pre-ordered withdrawal in the current epoch, it is increased; otherwise it starts from zero.
        withdrawal.shares = withdrawal.shares + shares;
        withdrawal.epoch = epoch.current;

        // -----------------------------
        // A withdrawal pre-order free space for further deposits, hence we must
        // update the vault capacity.
        //
        // The deposit receipt must also be updated in order to correctly update
        // the vault total deposits, shall the user initiate other withdrawal
        // pre-orders in the same epoch (as it is used for such computation).
        //
        // Steps:
        //   - estimate the increased capacity by computing the following proportion:
        //       withdrawed_shares : user_shares = x : user_deposits
        //   - use the found number for decreasing the current number of deposits.
        //   - update the user's deposit receipt [cumulativeAmount] value.
        VaultLib.DepositReceipt storage depositReceipt = depositReceipts[msg.sender];
        // NOTE: the user deposits to consider are only the ones for which a share has been minted.
        uint256 userDeposits = depositReceipt.cumulativeAmount;
        if (depositReceipt.epoch == epoch.current) {
            userDeposits -= depositReceipt.amount;
        }

        uint256 withdrawDepositEquivalent = (userDeposits * shares) / userShares;

        _state.liquidity.totalDeposit -= withdrawDepositEquivalent;
        depositReceipt.cumulativeAmount -= withdrawDepositEquivalent;
        // -----------------------------

        _state.withdrawals.newHeldShares += shares;

        _transfer(msg.sender, address(this), shares);

        emit InitiateWithdraw(shares);
    }

    /**
        @notice Completes a scheduled withdrawal from a past epoch. Uses finalized share price for the epoch.
     */
    function completeWithdraw() external whenNotPaused {
        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        // Checks if there is an initiated withdrawal request
        if (withdrawal.shares == 0) {
            revert WithdrawNotInitiated();
        }

        // At least one epoch must have passed since the start of the withdrawal
        if (withdrawal.epoch == getEpoch().current) {
            revert WithdrawTooEarly();
        }

        _completeWithdraw();
    }

    function _completeWithdraw() internal {
        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];

        uint256 pricePerShare = epochPricePerShare[withdrawal.epoch];
        uint256 amountToWithdraw = VaultLib.sharesToAsset(withdrawal.shares, pricePerShare, _shareDecimals);

        // NOTE: the user transferred the required shares to the vault when (s)he initiated the withdraw
        _state.withdrawals.heldShares -= withdrawal.shares;
        _state.liquidity.pendingWithdrawals -= amountToWithdraw;

        uint256 sharesToWithdraw = withdrawal.shares;
        withdrawal.shares = 0;
        _burn(address(this), sharesToWithdraw);
        IERC20(baseToken).safeTransfer(msg.sender, amountToWithdraw);

        emit Withdraw(amountToWithdraw);
    }

    function rescueShares() external isDead whenNotPaused {
        VaultLib.Withdrawal storage withdrawal = withdrawals[msg.sender];
        // If an uncompleted withdraw exists, complete it before starting a new one.
        if (withdrawal.shares > 0) {
            _completeWithdraw();
        }

        // NOTE: it will revert if there are no shares to further withdraw.
        _initiateWithdraw(0, true);

        // NOTE: due to the missing roll-epoch between the two withdraw phases, we have to:
        //       - account the withdrawed shares as held.
        //       - account the new pendingWithdrawals; due to the dead vault, we have to use the last price per share.
        _state.withdrawals.newHeldShares -= withdrawal.shares;
        _state.withdrawals.heldShares += withdrawal.shares;
        Epoch memory epoch = getEpoch();
        uint256 pricePerShare = epochPricePerShare[epoch.previous];
        uint256 newPendingWithdrawals = VaultLib.sharesToAsset(withdrawal.shares, pricePerShare, _shareDecimals);
        _state.liquidity.pendingWithdrawals += newPendingWithdrawals;

        // NOTE: as the withdrawal.epoch is the epoch.current one, we also have to fake it in order to use the right price per share.
        withdrawal.epoch = epoch.previous;

        _completeWithdraw();
    }

    // ------------------------------------------------------------------------
    // VAULT OPERATIONS
    // ------------------------------------------------------------------------

    /// @inheritdoc EpochControls
    function _beforeRollEpoch() internal virtual override isNotDead {
        _checkRole(ROLE_EPOCH_ROLLER);

        if (_state.killed) {
            // Sell all sideToken to be able to pay all the withdraws initiated after manual kill.
            (, uint256 sideTokens) = _tokenBalances();
            _sellSideTokens(sideTokens);
            _state.dead = true;
        }

        uint256 lockedLiquidity = notional();

        // [IL-NOTE]
        // In rare scenarios (ex. roundings or very tiny TVL vaults with high impact swap slippage) there can be small losses in a single epoch.
        // As a precautionary design we plan to revert and have the protocol DAO / admin cover such tiny amount.
        // Managing such scenarios at code level would increase codebase complexity without bringing any real benefit to the protocol.
        if (lockedLiquidity < _state.liquidity.newPendingPayoffs) {
            revert InsufficientLiquidity(
                bytes4(keccak256("_beforeRollEpoch()::lockedLiquidity <= _state.liquidity.newPendingPayoffs"))
            );
        }

        // NOTE: the share price needs to account also the payoffs
        lockedLiquidity -= _state.liquidity.newPendingPayoffs;

        // Computes the share price for the ending epoch:
        // - heldShares are the ones given back to the Vault in exchange of withdrawed tokens
        // - lockedLiquidity is the DVP portfolio value at the end of the epoch
        uint256 outstandingShares = totalSupply() - _state.withdrawals.heldShares;

        // NOTE: the share price cannot go to zero unless `_state.liquidity.newPendingPayoffs` is exactly equal to `lockedLiquidity`
        // - when all the locked liquidity is set aside for (pending) withdrawals and payoffs (lockedLiquidity = 0, we revert)
        // - when everyone withdrew, or during first epoch, `outstandingShares` is 0 -> sharePrice = 1
        uint256 sharePrice = VaultLib.pricePerShare(lockedLiquidity, outstandingShares, _shareDecimals);
        epochPricePerShare[getEpoch().current] = sharePrice;

        // NOTE: if for any reason lockedLiquidity results in 0 we avoid new depositors to receive no shares
        if (sharePrice == 0) {
            revert InsufficientLiquidity(bytes4(keccak256("_beforeRollEpoch()::sharePrice == 0")));
        }

        // Increase shares hold due to initiated withdrawals:
        _state.withdrawals.heldShares += _state.withdrawals.newHeldShares;

        // Reserve the liquidity needed to cover the withdrawals initiated in the current epoch:
        // NOTE: here we just account the amounts and we delay all the actual swaps to the final one in order to optimize them
        // NOTE: if sharePrice is zero, the users will receive zero from withdrawals
        uint256 newPendingWithdrawals = VaultLib.sharesToAsset(
            _state.withdrawals.newHeldShares,
            sharePrice,
            _shareDecimals
        );
        _state.liquidity.pendingWithdrawals += newPendingWithdrawals;
        // Cannot underflow since share price is computed taking into account residual lockedLiquidity
        lockedLiquidity -= newPendingWithdrawals;

        // Reset the counter for the next epoch:
        // NOTE: the held shares are burned when withdrawals are completed
        _state.withdrawals.newHeldShares = 0;

        // Set aside the payoff to be paid:
        _state.liquidity.pendingPayoffs += _state.liquidity.newPendingPayoffs;
        _state.liquidity.newPendingPayoffs = 0;

        // Mint shares related to new deposits performed during the closing epoch:
        // If vault has been killed, we go ahead minting shares and the last epoch depositors will have to call `rescueShares()`
        uint256 sharesToMint = VaultLib.assetToShares(_state.liquidity.pendingDeposits, sharePrice, _shareDecimals);
        _mint(address(this), sharesToMint);

        lockedLiquidity += _state.liquidity.pendingDeposits;
        _state.liquidity.pendingDeposits = 0;

        _state.liquidity.lockedInitially = lockedLiquidity;

        if (_state.killed) {
            // NOTE: no need to adjust balances, since all side tokens should be already converted
            return;
        }

        _adjustBalances();
        _state.liquidity.lockedInitially = notional();

        // NOTE: leave only an even number of base tokens for the DVP epoch
        if (lockedLiquidity % 2 != 0) {
            _state.liquidity.lockedInitially -= 1;
        }

        (uint256 baseTokens, ) = _tokenBalances();

        // NOTE: if after rebalance there's no enough liquidity to fulfill pending liabilities (see [IL-NOTE]) pause vault and signal to admins
        if (baseTokens < _state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs) {
            _pause();
            emit MissingLiquidity(_state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs - baseTokens);
        }
    }

    /// @notice Adjusts the balances in order to cover the liquidity locked for pending operations and obtain an equal weight portfolio.
    function _adjustBalances() internal {
        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        (uint256 baseTokens, uint256 sideTokens) = _tokenBalances();
        uint256 pendings = _state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs;

        if (baseTokens < pendings) {
            // We must cover the missing base tokens by selling an amount of side tokens:
            uint256 missingBaseTokens = pendings - baseTokens;
            uint256 sideTokensForMissingBaseTokens = exchange.getInputAmount(sideToken, baseToken, missingBaseTokens);

            // see [IL-NOTE]
            if (sideTokensForMissingBaseTokens > sideTokens) {
                revert InsufficientLiquidity(
                    bytes4(keccak256("_adjustBalances():sideTokensForMissingBaseTokens > sideTokens"))
                );
            }

            // Once we covered the missing base tokens, we still have to reach an equal weight portfolio
            // with residual liquidity, so we also have to sell half of the remaining side tokens
            uint256 halfOfRemainingSideTokens = (sideTokens - sideTokensForMissingBaseTokens) / 2;
            uint256 sideTokensToSell = sideTokensForMissingBaseTokens + halfOfRemainingSideTokens;
            _sellSideTokens(sideTokensToSell);
        } else {
            uint256 halfNotional = notional() / 2;
            uint256 targetSideTokens = exchange.getOutputAmount(baseToken, sideToken, halfNotional);

            // NOTE: here we are not interested in the number of exchanged base tokens
            _deltaHedge(int256(targetSideTokens) - int256(sideTokens));
        }
    }

    /// @inheritdoc EpochControls
    function _afterRollEpoch() internal virtual override {
        emit VaultTVL(getEpoch().current, v0());
    }

    /// @inheritdoc IVault
    function deltaHedge(int256 sideTokensAmount) external onlyDVP isNotDead whenNotPaused returns (uint256 baseTokens) {
        return _deltaHedge(sideTokensAmount);
    }

    /**
        @notice Adjust the portfolio by trading the given amount of side tokens.
        @param sideTokensAmount The amount of side tokens to buy (positive value) / sell (negative value).
        @return baseTokens The amount of exchanged base tokens.
     */
    function _deltaHedge(int256 sideTokensAmount) internal returns (uint256 baseTokens) {
        if (sideTokensAmount > 0) {
            uint256 amount = uint256(sideTokensAmount);
            return _buySideTokens(amount);
        } else {
            uint256 amount = uint256(-sideTokensAmount);
            return _sellSideTokens(amount);
        }
    }

    /**
        @notice Swap some of the available base tokens in order to obtain the provided amount of side tokens.
        @param amount The amount of side tokens to buy.
        @return baseTokens The amount of exchanged base tokens.
     */
    function _buySideTokens(uint256 amount) internal returns (uint256 baseTokens) {
        if (amount == 0) {
            return 0;
        }
        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        uint256 requiredInput = exchange.getInputAmountMax(baseToken, sideToken, amount);
        uint256 minRequiredInput = exchange.getInputAmount(baseToken, sideToken, amount);

        uint256 amountToApprove = requiredInput;
        uint256 availableBaseTokens = _notionalBaseTokens();

        // Since `requiredInput` should be an over-estimate, if available tokens are not enough to cover `getInputAmountMax`, try to approve all and do the swap
        if (availableBaseTokens < requiredInput) {
            amountToApprove = availableBaseTokens;

            // If even `minRequiredInput` cannot be covered, we reduce the required side tokens amount up to a X% safety margin to tackle with extreme scenarios where swap slippages may reduce the initial notional used for hedging computation
            if (availableBaseTokens < minRequiredInput) {
                amount -= (amount * _hedgeMargin) / 10000;
            }
        }

        IERC20(baseToken).safeApprove(exchangeAddress, amountToApprove);
        baseTokens = exchange.swapOut(baseToken, sideToken, amount, amountToApprove);

        // // Improvement: in order to standardize error response, catch a custom Adapter error when given input is < requested
        // try exchange.swapOut(baseToken, sideToken, amount, amountToApprove) returns (uint256 inputBaseTokens) {
        //     baseTokens = inputBaseTokens;
        // } catch (bytes memory reason) {
        //     // catch failing assert()
        //     if (bytes4(reason) == bytes4(keccak256("InsufficientInput()"))) {
        //         revert InsufficientLiquidity(bytes4(keccak256("_buySideTokens()")));
        //     }
        //     revert FailingDeltaHedge();
        // }
    }

    /**
        @notice Swap the provided amount of side tokens in exchange for base tokens.
        @param amount The amount of side tokens to sell.
        @return baseTokens The amount of exchanged base tokens.
     */
    function _sellSideTokens(uint256 amount) internal returns (uint256 baseTokens) {
        if (amount == 0) {
            return 0;
        }
        (, uint256 sideTokens) = _tokenBalances();
        if (amount > sideTokens) {
            revert InsufficientLiquidity(bytes4(keccak256("_sellSideTokens()")));
        }

        address exchangeAddress = _addressProvider.exchangeAdapter();
        if (exchangeAddress == address(0)) {
            revert AddressZero();
        }
        IExchange exchange = IExchange(exchangeAddress);

        IERC20(sideToken).safeApprove(exchangeAddress, amount);
        baseTokens = exchange.swapIn(sideToken, baseToken, amount);
    }

    /// @inheritdoc IVault
    function reservePayoff(uint256 residualPayoff) external onlyDVP {
        if (residualPayoff > notional()) {
            revert InsufficientLiquidity(bytes4(keccak256("reservePayoff()")));
        }
        _state.liquidity.newPendingPayoffs = residualPayoff;
    }

    /// @inheritdoc IVault
    function transferPayoff(address recipient, uint256 amount, bool isPastEpoch) external onlyDVP whenNotPaused {
        if (amount == 0) {
            return;
        }

        if (isPastEpoch) {
            if (amount > _state.liquidity.pendingPayoffs) {
                revert ExceedsAvailable();
            }
            _state.liquidity.pendingPayoffs -= amount;
        } else {
            // NOTE: it should never happen as `_deltaHedge()` must always be executed before transfers
            if (amount > _notionalBaseTokens()) {
                revert ExceedsAvailable();
            }
        }

        IERC20(baseToken).safeTransfer(recipient, amount);
    }

    /// @dev Checks if given deposit is allowed to be made and calls nft usage callback function if needed
    function _usePriorityAccess(uint256 amount, address receiver, uint256 accessTokenId) private {
        if (priorityAccessFlag) {
            IVaultAccessNFT nft = IVaultAccessNFT(_addressProvider.vaultAccessNFT());
            if (accessTokenId == 0 || nft.ownerOf(accessTokenId) != receiver) {
                revert PriorityAccessDenied();
            }
            if (amount > nft.priorityAmount(accessTokenId)) {
                revert PriorityAccessDenied();
            }
            nft.decreasePriorityAmount(accessTokenId, amount);
        }
    }

    /**
        @notice If ever stuck in InsufficientLiquidity error we sell all side tokens to maximize the amount that can be recovered
        @dev Even if epoch can't roll over, users can still call `IG.burn()` and `Vault.completeWitdraw()`
     */
    function emergencyRebalance() external onlyRole(ROLE_ADMIN) {
        _checkEpochFinished();
        (, uint256 sideTokens) = _tokenBalances();
        _sellSideTokens(sideTokens);
    }
}
