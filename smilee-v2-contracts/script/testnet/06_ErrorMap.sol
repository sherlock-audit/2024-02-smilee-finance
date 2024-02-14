// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

contract ErrorMap is Script {
    // AddressProvider.sol
    bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));

    // DVP.sol
    bytes4 constant NotEnoughNotional = bytes4(keccak256("NotEnoughNotional()"));
    bytes4 constant PositionNotFound = bytes4(keccak256("PositionNotFound()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));
    bytes4 constant MissingMarketOracle = bytes4(keccak256("MissingMarketOracle()"));
    bytes4 constant MissingPriceOracle = bytes4(keccak256("MissingPriceOracle()"));
    bytes4 constant MissingFeeManager = bytes4(keccak256("MissingFeeManager()"));
    bytes4 constant SlippedMarketValue = bytes4(keccak256("SlippedMarketValue()"));
    bytes4 constant VaultDead = bytes4(keccak256("VaultDead()"));

    // EpochControls.sol
    bytes4 constant EpochFinished = bytes4(keccak256("EpochFinished()"));

    // FeeManager.sol
    bytes4 constant NoEnoughFundsFromSender = bytes4(keccak256("NoEnoughFundsFromSender()"));
    bytes4 constant OutOfAllowedRange = bytes4(keccak256("OutOfAllowedRange()"));

    // IG.sol
    // bytes4 constant OutOfAllowedRange = bytes4(keccak256("OutOfAllowedRange()"));

    // MarketOracle.sol
    // bytes4 constant OutOfAllowedRange = bytes4(keccak256("OutOfAllowedRange()"));

    // PositionManager.sol
    // bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));
    bytes4 constant InvalidTokenID = bytes4(keccak256("InvalidTokenID()"));
    bytes4 constant NotOwner = bytes4(keccak256("NotOwner()"));
    bytes4 constant PositionExpired = bytes4(keccak256("PositionExpired()"));

    // Registry.sol
    bytes4 constant MissingAddress = bytes4(keccak256("MissingAddress()"));

    // Vault.sol
    // bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant DVPAlreadySet = bytes4(keccak256("DVPAlreadySet()"));
    bytes4 constant DVPNotSet = bytes4(keccak256("DVPNotSet()"));
    bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));
    bytes4 constant ExceedsMaxDeposit = bytes4(keccak256("ExceedsMaxDeposit()"));
    bytes4 constant ExistingIncompleteWithdraw = bytes4(keccak256("ExistingIncompleteWithdraw()"));
    bytes4 constant NothingToRescue = bytes4(keccak256("NothingToRescue()"));
    bytes4 constant NothingToWithdraw = bytes4(keccak256("NothingToWithdraw()"));
    bytes4 constant OnlyDVPAllowed = bytes4(keccak256("OnlyDVPAllowed()"));
    bytes4 constant PriorityAccessDenied = bytes4(keccak256("PriorityAccessDenied()"));
    bytes4 constant SecondaryMarketNotAllowed = bytes4(keccak256("SecondaryMarketNotAllowed()"));
    // bytes4 constant VaultDead = bytes4(keccak256("VaultDead()"));
    bytes4 constant VaultNotDead = bytes4(keccak256("VaultNotDead()"));
    bytes4 constant WithdrawNotInitiated = bytes4(keccak256("WithdrawNotInitiated()"));
    bytes4 constant WithdrawTooEarly = bytes4(keccak256("WithdrawTooEarly()"));
    bytes4 constant NotManuallyKilled = bytes4(keccak256("NotManuallyKilled()"));

    // VaultProxy.sol
    bytes4 constant DepositToNonVaultContract = bytes4(keccak256("DepositToNonVaultContract()"));

    // IDVP.sol
    // bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant InvalidStrategy = bytes4(keccak256("InvalidStrategy()"));

    // AmountsMath.sol
    bytes4 constant AddOverflow = bytes4(keccak256("AddOverflow()"));
    bytes4 constant MulOverflow = bytes4(keccak256("MulOverflow()"));
    bytes4 constant SubUnderflow = bytes4(keccak256("SubUnderflow()"));
    bytes4 constant TooManyDecimals = bytes4(keccak256("TooManyDecimals()"));

    // EpochController.sol
    bytes4 constant EpochNotFinished = bytes4(keccak256("EpochNotFinished()"));

    // EpochFrequency.sol
    bytes4 constant UnsupportedFrequency = bytes4(keccak256("UnsupportedFrequency()"));

    // FinanceIGPrice.sol
    bytes4 constant PriceZero = bytes4(keccak256("PriceZero()"));
    bytes4 constant OutOfRange = bytes4(keccak256("OutOfRange()"));

    // SignedMath.sol
    bytes4 constant Overflow = bytes4(keccak256("Overflow()"));

    // TokensPair.sol
    // bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant SameToken = bytes4(keccak256("SameToken()"));
    bytes4 constant InvalidToken = bytes4(keccak256("InvalidToken(address)"));

    // WadTime.sol
    bytes4 constant InvalidInput = bytes4(keccak256("InvalidInput()"));

    // VaultAccessNFT.sol
    bytes4 constant CallerNotVault = bytes4(keccak256("CallerNotVault()"));
    // bytes4 constant ExceedsAvailable = bytes4(keccak256("ExceedsAvailable()"));

    // SwapAdapterRouter.sol
    // bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant Slippage = bytes4(keccak256("Slippage()"));
    bytes4 constant SwapZero = bytes4(keccak256("SwapZero()"));

    // ChainlinkPriceOracle.sol
    // bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant TokenNotSupported = bytes4(keccak256("TokenNotSupported()"));
    // bytes4 constant PriceZero = bytes4(keccak256("PriceZero()"));

    // UniswapAdapter.sol
    // bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    bytes4 constant PathNotValid = bytes4(keccak256("PathNotValid()"));
    bytes4 constant PathNotSet = bytes4(keccak256("PathNotSet()"));
    bytes4 constant PathLengthNotValid = bytes4(keccak256("PathLengthNotValid()"));
    bytes4 constant PoolDoesNotExist = bytes4(keccak256("PoolDoesNotExist()"));
    bytes4 constant NotImplemented = bytes4(keccak256("NotImplemented()"));

    // AdminAccess.sol
    bytes4 constant CallerNotAdmin = bytes4(keccak256("CallerNotAdmin()"));
    bytes4 constant AdminAddressZero = bytes4(keccak256("AdminAddressZero()"));

    // TestnetPriceOracle.sol
    // bytes4 constant AddressZero = bytes4(keccak256("AddressZero()"));
    // bytes4 constant TokenNotSupported = bytes4(keccak256("TokenNotSupported()"));
    // bytes4 constant PriceZero = bytes4(keccak256("PriceZero()"));
    bytes4 constant PriceTooHigh = bytes4(keccak256("PriceTooHigh()"));

    // TestnetSwapAdapter.sol
    // bytes4 constant PriceZero = bytes4(keccak256("PriceZero()"));
    bytes4 constant TransferFailed = bytes4(keccak256("TransferFailed()"));

    // TestnetToken.sol
    bytes4 constant NotInitialized = bytes4(keccak256("NotInitialized()"));
    bytes4 constant Unauthorized = bytes4(keccak256("Unauthorized()"));

    constructor() {}

    // NOTE: this is the script entrypoint
    function run() external view {
        _printErrors();
    }

    function _printErrors() internal view {
        console.log("AddressZero");
        console.logBytes4(AddressZero);
        console.log("NotEnoughNotional");
        console.logBytes4(NotEnoughNotional);
        console.log("PositionNotFound");
        console.logBytes4(PositionNotFound);
        console.log("CantBurnMoreThanMinted");
        console.logBytes4(CantBurnMoreThanMinted);
        console.log("MissingMarketOracle");
        console.logBytes4(MissingMarketOracle);
        console.log("MissingPriceOracle");
        console.logBytes4(MissingPriceOracle);
        console.log("MissingFeeManager");
        console.logBytes4(MissingFeeManager);
        console.log("SlippedMarketValue");
        console.logBytes4(SlippedMarketValue);
        console.log("VaultDead");
        console.logBytes4(VaultDead);
        console.log("EpochFinished");
        console.logBytes4(EpochFinished);
        console.log("NoEnoughFundsFromSender");
        console.logBytes4(NoEnoughFundsFromSender);
        console.log("OutOfAllowedRange");
        console.logBytes4(OutOfAllowedRange);
        console.log("OutOfAllowedRange");
        console.logBytes4(OutOfAllowedRange);
        console.log("OutOfAllowedRange");
        console.logBytes4(OutOfAllowedRange);
        console.log("CantBurnMoreThanMinted");
        console.logBytes4(CantBurnMoreThanMinted);
        console.log("InvalidTokenID");
        console.logBytes4(InvalidTokenID);
        console.log("NotOwner");
        console.logBytes4(NotOwner);
        console.log("PositionExpired");
        console.logBytes4(PositionExpired);
        console.log("MissingAddress");
        console.logBytes4(MissingAddress);
        console.log("AddressZero");
        console.logBytes4(AddressZero);
        console.log("AmountZero");
        console.logBytes4(AmountZero);
        console.log("DVPAlreadySet");
        console.logBytes4(DVPAlreadySet);
        console.log("DVPNotSet");
        console.logBytes4(DVPNotSet);
        console.log("ExceedsAvailable");
        console.logBytes4(ExceedsAvailable);
        console.log("ExceedsMaxDeposit");
        console.logBytes4(ExceedsMaxDeposit);
        console.log("ExistingIncompleteWithdraw");
        console.logBytes4(ExistingIncompleteWithdraw);
        console.log("NothingToRescue");
        console.logBytes4(NothingToRescue);
        console.log("NothingToWithdraw");
        console.logBytes4(NothingToWithdraw);
        console.log("OnlyDVPAllowed");
        console.logBytes4(OnlyDVPAllowed);
        console.log("PriorityAccessDenied");
        console.logBytes4(PriorityAccessDenied);
        console.log("SecondaryMarketNotAllowed");
        console.logBytes4(SecondaryMarketNotAllowed);
        console.log("VaultDead");
        console.logBytes4(VaultDead);
        console.log("VaultNotDead");
        console.logBytes4(VaultNotDead);
        console.log("WithdrawNotInitiated");
        console.logBytes4(WithdrawNotInitiated);
        console.log("WithdrawTooEarly");
        console.logBytes4(WithdrawTooEarly);
        console.log("NotManuallyKilled");
        console.logBytes4(NotManuallyKilled);
        console.log("DepositToNonVaultContract");
        console.logBytes4(DepositToNonVaultContract);
        console.log("AmountZero");
        console.logBytes4(AmountZero);
        console.log("InvalidStrategy");
        console.logBytes4(InvalidStrategy);
        console.log("AddOverflow");
        console.logBytes4(AddOverflow);
        console.log("MulOverflow");
        console.logBytes4(MulOverflow);
        console.log("SubUnderflow");
        console.logBytes4(SubUnderflow);
        console.log("TooManyDecimals");
        console.logBytes4(TooManyDecimals);
        console.log("EpochNotFinished");
        console.logBytes4(EpochNotFinished);
        console.log("UnsupportedFrequency");
        console.logBytes4(UnsupportedFrequency);
        console.log("PriceZero");
        console.logBytes4(PriceZero);
        console.log("OutOfRange");
        console.logBytes4(OutOfRange);
        console.log("Overflow");
        console.logBytes4(Overflow);
        console.log("AddressZero");
        console.logBytes4(AddressZero);
        console.log("SameToken");
        console.logBytes4(SameToken);
        console.log("InvalidToken");
        console.logBytes4(InvalidToken);
        console.log("InvalidInput");
        console.logBytes4(InvalidInput);
        console.log("CallerNotVault");
        console.logBytes4(CallerNotVault);
        console.log("ExceedsAvailable");
        console.logBytes4(ExceedsAvailable);
        console.log("AddressZero");
        console.logBytes4(AddressZero);
        console.log("Slippage");
        console.logBytes4(Slippage);
        console.log("SwapZero");
        console.logBytes4(SwapZero);
        console.log("AddressZero");
        console.logBytes4(AddressZero);
        console.log("TokenNotSupported");
        console.logBytes4(TokenNotSupported);
        console.log("PriceZero");
        console.logBytes4(PriceZero);
        console.log("AddressZero");
        console.logBytes4(AddressZero);
        console.log("PathNotValid");
        console.logBytes4(PathNotValid);
        console.log("PathNotSet");
        console.logBytes4(PathNotSet);
        console.log("PathLengthNotValid");
        console.logBytes4(PathLengthNotValid);
        console.log("PoolDoesNotExist");
        console.logBytes4(PoolDoesNotExist);
        console.log("NotImplemented");
        console.logBytes4(NotImplemented);
        console.log("CallerNotAdmin");
        console.logBytes4(CallerNotAdmin);
        console.log("AdminAddressZero");
        console.logBytes4(AdminAddressZero);
        console.log("AddressZero");
        console.logBytes4(AddressZero);
        console.log("TokenNotSupported");
        console.logBytes4(TokenNotSupported);
        console.log("PriceZero");
        console.logBytes4(PriceZero);
        console.log("PriceTooHigh");
        console.logBytes4(PriceTooHigh);
        console.log("PriceZero");
        console.logBytes4(PriceZero);
        console.log("TransferFailed");
        console.logBytes4(TransferFailed);
        console.log("NotInitialized");
        console.logBytes4(NotInitialized);
        console.log("Unauthorized");
        console.logBytes4(Unauthorized);
    }
}
