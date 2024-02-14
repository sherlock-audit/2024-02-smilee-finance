// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {AmountsMath} from "../lib/AmountsMath.sol";

/// @dev everything is expressed in Wad (18 decimals)
contract TestnetPriceOracle is IPriceOracle, Ownable {
    using AmountsMath for uint256;

    struct OracleValue {
        uint256 value;
        uint256 lastUpdate;
    }

    address public referenceToken;
    mapping(address => OracleValue) internal _prices;

    error AddressZero();
    error TokenNotSupported();
    error PriceZero();
    error PriceTooHigh();

    constructor(address referenceToken_) Ownable() {
        referenceToken = referenceToken_;
        setTokenPrice(referenceToken, 1e18); // 1
    }

    // NOTE: the price is with 18 decimals and is expected to be in referenceToken
    function setTokenPrice(address token, uint256 price) public onlyOwner {
        if (token == address(0)) {
            revert AddressZero();
        }

        if (price > type(uint256).max / 1e18) {
            revert PriceTooHigh();
        }

        OracleValue storage price_ = _prices[token];
        price_.value = price;
        price_.lastUpdate = block.timestamp;
    }

    /**
        @notice Return Price of token in referenceToken
        @param token Address of token
        @return price Price of token in referenceToken
     */
    function getTokenPrice(address token) public view returns (uint256) {
        if (token == address(0)) {
            revert AddressZero();
        }

        if (!_priceIsSet(token)) {
            revert TokenNotSupported();
        }

        OracleValue memory price = _prices[token];
        // TBD: revert if price is too old or also return the update time and let the called decide.
        return price.value;
    }

    function _priceIsSet(address token) internal view returns (bool) {
        return _prices[token].lastUpdate > 0;
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address token0, address token1) external view returns (uint256) {
        uint256 token0Price = getTokenPrice(token0);
        uint256 token1Price = getTokenPrice(token1);

        if (token1Price == 0) {
            // TBD: improve error
            revert PriceZero();
        }

        return token0Price.wdiv(token1Price);
    }
}
