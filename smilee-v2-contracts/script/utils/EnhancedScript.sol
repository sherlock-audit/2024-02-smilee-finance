// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

// NOTE: it has to be a contract; if we make it a library, Foundry crash without reasons... :/
abstract contract EnhancedScript is Script {

    error ZeroAddress(string name);

    function _checkZeroAddress(address addr, string memory name) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress(name);
        }
    }

    function _getTransactionLogs(
        string memory scriptFilename,
        string memory run
    ) internal view returns (string memory) {
        string memory directory = string.concat(vm.projectRoot(), "/broadcast/", scriptFilename, "/", vm.toString(block.chainid), "/");
        string memory file = string.concat("run-", run, ".json");
        string memory path = string.concat(directory, file);

        return vm.readFile(path);
    }

    function _getLatestTransactionLogs(
        string memory scriptFilename
    ) internal view returns (string memory) {
        return _getTransactionLogs(scriptFilename, "latest");
    }

    function _getJsonPath(string memory contractName) private pure returns (string memory) {
        return string.concat("$.transactions[?(@.contractName == '", contractName, "' && @.transactionType == 'CREATE')].contractAddress");
    }

    function _readAddress(string memory transactionLogs, string memory contractName) internal returns (address) {
        // NOTE: as a key it wants a "JSONPath"
        return stdJson.readAddress(transactionLogs, _getJsonPath(contractName));
    }
}
