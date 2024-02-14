// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Vault} from "../../src/Vault.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/05_Vault.s.sol:VaultOps --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv --sig 'fillVault(address,uint256)' <VAULT_ADDRESS> <AMOUNT>
 */
contract VaultOps is EnhancedScript {
    uint256 internal _deployerPrivateKey;
    address internal _deployerAddress;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
    }

    function run() external {}

   function pauseVault(address vaultAddr) public {
         Vault vault = Vault(vaultAddr);

        vm.startBroadcast(_deployerPrivateKey);
        vault.changePauseState();
        vm.stopBroadcast();
    }

    function killVault(address vaultAddr) public {
        Vault vault = Vault(vaultAddr);

        vm.startBroadcast(_deployerPrivateKey);
        vault.killVault();
        vm.stopBroadcast();
    }

}
