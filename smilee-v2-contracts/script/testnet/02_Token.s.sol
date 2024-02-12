// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {AddressProvider} from "../../src/AddressProvider.sol";
import {TestnetToken} from "../../src/testnet/TestnetToken.sol";
import {TestnetPriceOracle} from "../../src/testnet/TestnetPriceOracle.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a local network:
        #   NOTE: Make sue that the local node (anvil) is running...
        forge script script/testnet/02_Token.s.sol:DeployToken --fork-url $RPC_LOCALNET --broadcast -vvvv --sig 'deployToken(string memory)' <SYMBOL>
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/testnet/02_Token.s.sol:DeployToken --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv --sig 'deployToken(string memory)' <SYMBOL>
 */
contract DeployToken is EnhancedScript {

    uint256 internal _deployerPrivateKey;
    AddressProvider internal _ap;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _ap = AddressProvider(_readAddress(txLogs, "AddressProvider"));
    }

    function run() external {
        address sETH = _deployToken("ETH");
        console.log(string.concat("Token sETH deployed at"), sETH);
        setTokenPrice(sETH, 1600e18);
    }

    function deployToken(string memory symbol) public {
        address sToken = _deployToken(symbol);
        console.log(string.concat("Token s", symbol, " deployed at"), sToken);
    }

    function _deployToken(string memory symbol) internal returns (address) {
        string memory tokenName = string.concat("Smilee ", symbol);
        string memory tokenSymbol = string.concat("s", symbol);

        vm.startBroadcast(_deployerPrivateKey);

        TestnetToken sToken = new TestnetToken(tokenName, tokenSymbol);

        sToken.setAddressProvider(address(_ap));

        // TBD: mint tokens to owner ?

        vm.stopBroadcast();

        return address(sToken);
    }

    function setTokenPrice(address token, uint256 price) public {
        TestnetPriceOracle priceOracle = TestnetPriceOracle(_ap.priceOracle());

        vm.startBroadcast(_deployerPrivateKey);
        priceOracle.setTokenPrice(token, price);
        vm.stopBroadcast();
    }


    function mint(address tokenAddr, address recipient, uint256 amount) public {
        TestnetToken sToken = TestnetToken(tokenAddr);

        vm.startBroadcast(_deployerPrivateKey);
        sToken.mint(recipient, amount);
        vm.stopBroadcast();
    }
}
