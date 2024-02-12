// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Amount, AmountHelper} from "src/lib/Amount.sol";
import {AmountsMath} from "src/lib/AmountsMath.sol";
import {DVPType} from "src/lib/DVPType.sol";
import {Epoch, EpochController} from "src/lib/EpochController.sol";
import {EpochFrequency} from "src/lib/EpochFrequency.sol";
import {Finance} from "src/lib/Finance.sol";
import {TimeLockedFinanceParameters, FinanceParameters, FinanceIG, VolatilityParameters} from "src/lib/FinanceIG.sol";
import {FinanceIGDelta} from "src/lib/FinanceIGDelta.sol";
import {FinanceIGPayoff} from "src/lib/FinanceIGPayoff.sol";
import {FinanceIGPrice} from "src/lib/FinanceIGPrice.sol";
import {Notional} from "src/lib/Notional.sol";
import {OptionStrategy} from "src/lib/OptionStrategy.sol";
import {Position} from "src/lib/Position.sol";
import {SignedMath} from "src/lib/SignedMath.sol";
import {TimeLockedBool, TimeLockedUInt, TimeLock} from "src/lib/TimeLock.sol";
import {TokensPair} from "src/lib/TokensPair.sol";
import {VaultLib} from "src/lib/VaultLib.sol";
import {WadTime} from "src/lib/WadTime.sol";

/*
    NOTE: Used only to deploy all libs

    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts
    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/00_Libraries.s.sol:DeployLibraries --fork-url $RPC_LOCALNET --broadcast -vvvv
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/00_Libraries.s.sol:DeployLibraries --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv
 */
contract LibraryDeployer {
    using TimeLock for TimeLockedUInt;
    using Notional for Notional.Info;

    Amount amountOne;
    TimeLockedUInt tlui;
    TimeLockedFinanceParameters tfp;
    Notional.Info notionalInfo;
    VolatilityParameters tvp;

    constructor() {}

    function deployLibraries() public {
        amountOne = Amount(1, 1);
        Amount memory amountTwo = Amount(2, 2);
        AmountHelper.increase(amountOne, amountTwo);
        AmountsMath.add(1, 1);
        Epoch memory epoch = Epoch(1, 1, 1, 1, 1);
        EpochController.timeToNextEpoch(epoch);
        EpochFrequency.validityCheck(1);
        Finance.getUtilizationRate(1, 1, 1);
        tlui = TimeLockedUInt(1, 2, 3);
        TimeLockedBool memory tmlb = TimeLockedBool(true, true, 1);
        tfp = TimeLockedFinanceParameters(tlui, tlui, tlui, tlui, tmlb);
        tvp = VolatilityParameters(1, 1, 1, 1, 1, 1);
        FinanceParameters memory fp = FinanceParameters(12, 13, amountOne, 123, 124, 2, tfp, 1, tvp);
        FinanceIG.getPayoffPercentages(fp, 1);
        FinanceIGDelta.bullDelta(0, 0, 0, 0);
        FinanceIGPayoff.igPayoffInRange(100000, 2);
        FinanceIGPrice.d1Parts(1, 2, 3);
        notionalInfo.setInitial(123, amountOne);
        Position.getID(address(this), 1);
        SignedMath.castInt(1);
        tfp.sigmaMultiplier.set(1, 2);
        TokensPair.Pair memory pair = TokensPair.Pair(address(this), address(this));
        TokensPair.getDecimals(pair);
        VaultLib.assetToShares(0, 0, 18);
        WadTime.nYears(2);
    }
}

contract DeployLibraries is Script {
    uint256 internal _deployerPrivateKey;
    address internal _deployerAddress;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
    }

    // NOTE: this is the script entrypoint
    function run() external {
        // The broadcast will records the calls and contract creations made and will replay them on-chain.
        // For reference, the broadcast transaction logs will be stored in the broadcast directory.
        vm.startBroadcast(_deployerPrivateKey);
        _doSomething();
        vm.stopBroadcast();
    }

    function _doSomething() internal {
        console.log("Deploying libraries");
        new LibraryDeployer();
    }
}
