// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {console} from "forge-std/console.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {ChainlinkPriceOracle} from "@project/providers/chainlink/ChainlinkPriceOracle.sol";
import {SwapAdapterRouter} from "@project/providers/SwapAdapterRouter.sol";
import {UniswapAdapter} from "@project/providers/uniswap/UniswapAdapter.sol";
import {EnhancedScript} from "../utils/EnhancedScript.sol";

/*
    Reference: https://book.getfoundry.sh/tutorials/solidity-scripting
    ToDo: see https://book.getfoundry.sh/tutorials/best-practices#scripts

    Usage:
        source .env

        # To deploy [and verify] the contracts
        # - On a real network:
        #   ToDo: see https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw
        forge script script/mainnet/02_Token.s.sol:TokenOps --rpc-url $RPC_MAINNET --broadcast [--verify] -vvvv --sig 'deployToken(string memory)' <SYMBOL>
 */
contract TokenOps is EnhancedScript {

    uint256 internal _adminPrivateKey;
    AddressProvider internal _ap;
    UniswapAdapter internal _uniswapAdapter;

    constructor() {
        // Load the private key that will be used for signing the transactions:
        _adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");

        string memory txLogs = _getLatestTransactionLogs("01_CoreFoundations.s.sol");
        _ap = AddressProvider(_readAddress(txLogs, "AddressProvider"));
        _uniswapAdapter = UniswapAdapter(_readAddress(txLogs, "UniswapAdapter"));
    }

    function run() external view {
        console.log("Please run a specific task");
    }

    function setChainlinkPriceFeedForToken(address token, address chainlinkFeedAddress) public {
        ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(_ap.priceOracle());

        vm.startBroadcast(_adminPrivateKey);
        priceOracle.setPriceFeed(token, chainlinkFeedAddress);
        vm.stopBroadcast();
    }

    function setChainlinkPriceFeedMaxDelay(address token, uint256 maxDelay) public {
        ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(_ap.priceOracle());

        vm.startBroadcast(_adminPrivateKey);
        priceOracle.setPriceFeedMaxDelay(token, maxDelay);
        vm.stopBroadcast();
    }

    function setSwapAdapterForTokens(address tokenIn, address tokenOut, address swapAdapter) public {
        SwapAdapterRouter swapAdapterRouter = SwapAdapterRouter(_ap.exchangeAdapter());

        vm.startBroadcast(_adminPrivateKey);
        swapAdapterRouter.setAdapter(tokenIn, tokenOut, swapAdapter);
        swapAdapterRouter.setAdapter(tokenOut, tokenIn, swapAdapter);
        vm.stopBroadcast();
    }

    function useUniswapAdapterWithTokens(address token0, address token1) public {
        SwapAdapterRouter swapAdapterRouter = SwapAdapterRouter(_ap.exchangeAdapter());

        vm.startBroadcast(_adminPrivateKey);
        swapAdapterRouter.setAdapter(token0, token1, address(_uniswapAdapter));
        swapAdapterRouter.setAdapter(token1, token0, address(_uniswapAdapter));
        vm.stopBroadcast();
    }

    function setSwapAcceptedSlippageForTokens(address tokenIn, address tokenOut, uint256 value) public {
        SwapAdapterRouter swapAdapterRouter = SwapAdapterRouter(_ap.exchangeAdapter());

        vm.startBroadcast(_adminPrivateKey);
        swapAdapterRouter.setSlippage(tokenIn, tokenOut, value);
        swapAdapterRouter.setSlippage(tokenOut, tokenIn, value);
        vm.stopBroadcast();
    }

    function setUniswapPath(address tokenIn, address tokenOut, bytes memory path) public {
        UniswapAdapter uniswapAdapter = UniswapAdapter(SwapAdapterRouter(_ap.exchangeAdapter()).getAdapter(tokenIn, tokenOut));

        vm.startBroadcast(_adminPrivateKey);
        uniswapAdapter.setPath(path, tokenIn, tokenOut);
        vm.stopBroadcast();
    }

    function printUniswapPath(address tokenIn, address tokenOut, uint24 fee) public {
        // 10000 is 1%
        //  3000 is 0.3%
        //   500 is 0.05%
        bytes memory path = abi.encodePacked(tokenIn, fee, tokenOut);

        vm.startBroadcast(_adminPrivateKey);
        console.log("path is");
        console.logBytes(path);
        vm.stopBroadcast();
    }

    function printUniswapPathWithHop(address tokenIn, uint24 feeMiddleIn, address tokenMiddle, uint24 feeMiddleOut, address tokenOut) public {
        // 10000 is 1%
        //  3000 is 0.3%
        //   500 is 0.05%
        bytes memory path = abi.encodePacked(tokenIn, feeMiddleIn, tokenMiddle, feeMiddleOut, tokenOut);

        vm.startBroadcast(_adminPrivateKey);
        console.log("path is");
        console.logBytes(path);
        vm.stopBroadcast();
    }

    function setTokenRiskFreeRate(address token, uint256 value) public {
        MarketOracle marketOracle = MarketOracle(_ap.marketOracle());

        vm.startBroadcast(_adminPrivateKey);
        marketOracle.setRiskFreeRate(token, value);
        vm.stopBroadcast();
    }

    function setImpliedVolatility(address token0, address token1, uint256 frequency, uint256 value) public {
        MarketOracle marketOracle = MarketOracle(_ap.marketOracle());

        vm.startBroadcast(_adminPrivateKey);
        marketOracle.setImpliedVolatility(token0, token1, frequency, value);
        vm.stopBroadcast();
    }
}
