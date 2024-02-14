// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMarketOracle} from "./interfaces/IMarketOracle.sol";

/// @dev everything is expressed in Wad (18 decimals)
contract MarketOracle is IMarketOracle, AccessControl {
    struct OracleValue {
        uint256 value;
        uint256 lastUpdate;
    }

    struct DelayParameters {
        uint256 delay;
        // Disable the check of the delay.
        bool disabled;
    }

    // Default maximum elapsed time used to check the value as old.
    uint256 public defaultMaxDelayFromLastUpdate;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    /// @dev index is computed in _getImpliedVolatility
    mapping(bytes32 => OracleValue) internal _impliedVolatility;
    /// @dev index is the base token address
    mapping(address => OracleValue) internal _riskFreeRate;
    /// @dev max delay from last update for each token and frequency
    mapping(bytes32 => DelayParameters) internal _maxDelay;

    error OutOfAllowedRange();
    error AddressZero();
    error StaleOracleValue(address token0, address token1, uint256 frequency);

    event ChangedIV(address indexed token0, address indexed token1, uint256 frequency, uint256 value, uint256 oldValue);
    event ChangedTokenPriceFeedMaxDelay(
        address indexed token0,
        address indexed token1,
        uint256 timeWindows,
        uint256 value,
        bool disabled
    );
    event ChangedRFR(address indexed token, uint256 value, uint256 oldValue);
    event ChangedDefaultMaxDelay(uint256 value);
    event ChangedMaxDelay(uint256 value);

    constructor() AccessControl() {
        defaultMaxDelayFromLastUpdate = 1 hours;

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    function _getIndex(address token0, address token1, uint256 timeWindow) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token0, token1, timeWindow));
    }

    function setMaxDefaultDelay(uint256 defaultMaxDelay) external {
        _checkRole(ROLE_ADMIN);

        defaultMaxDelayFromLastUpdate = defaultMaxDelay;

        emit ChangedDefaultMaxDelay(defaultMaxDelay);
    }

    function setDelay(
        address token0,
        address token1,
        uint256 timeWindow,
        uint256 delay,
        bool disabled
    ) external {
        _checkRole(ROLE_ADMIN);
        if (token0 == address(0) || token1 == address(0)) {
            revert AddressZero();
        }
        bytes32 index = _getIndex(token0, token1, timeWindow);
        DelayParameters storage delayParameters = _maxDelay[index];

        delayParameters.delay = delay;
        delayParameters.disabled = disabled;

        emit ChangedTokenPriceFeedMaxDelay(token0, token1, timeWindow, delay, disabled);
    }

    function getMaxDelay(address token0, address token1, uint256 timeWindow) external view returns (uint256 maxDelay_, bool disabled) {
        DelayParameters memory delayParameters = _getDelay(token0, token1, timeWindow);

        return (delayParameters.delay, delayParameters.disabled);
    }

    function _getDelay(address token0, address token1, uint256 timeWindow) internal view returns(DelayParameters memory _delayParameters) {
        bytes32 index = _getIndex(token0, token1, timeWindow);
        _delayParameters = _maxDelay[index];

        if (_delayParameters.delay == 0) {
            _delayParameters.delay = defaultMaxDelayFromLastUpdate;
        }
    }

    function _getImpliedVolatility(
        address baseToken,
        address sideToken,
        uint256 timeWindow
    ) internal view returns (OracleValue storage) {
        bytes32 index = _getIndex(baseToken, sideToken, timeWindow);
        return _impliedVolatility[index];
    }

    /// @inheritdoc IMarketOracle
    function getImpliedVolatility(
        address token0,
        address token1,
        uint256 strikePrice,
        uint256 frequency
    ) external view returns (uint256 iv) {
        // NOTE: strike ignored by the current IG-only implementation.
        strikePrice;

        OracleValue storage iv_ = _getImpliedVolatility(token0, token1, frequency);

        if (iv_.lastUpdate == 0) {
            // NOTE: it's up to the deployer to set the right values; this is just a safe last resort.
            return 1e18;
        }

        DelayParameters memory delayParameters = _getDelay(token0, token1, frequency);

        if (!delayParameters.disabled) {
            if (iv_.lastUpdate + delayParameters.delay < block.timestamp) {
                revert StaleOracleValue(token0, token1, frequency);
            }
        }

        iv = iv_.value;
    }

    function setImpliedVolatility(address token0, address token1, uint256 frequency, uint256 value) public {
        _checkRole(ROLE_ADMIN);
        if (value < 0.01e18 || value > 1000e18) {
            revert OutOfAllowedRange();
        }

        OracleValue storage iv_ = _getImpliedVolatility(token0, token1, frequency);

        uint256 old = iv_.value;
        iv_.value = value;
        iv_.lastUpdate = block.timestamp;

        emit ChangedIV(token0, token1, frequency, value, old);
    }

    function getImpliedVolatilityLastUpdate(
        address token0,
        address token1,
        uint256 frequency
    ) external view returns (uint256 lastUpdate) {
        OracleValue storage iv_ = _getImpliedVolatility(token0, token1, frequency);
        lastUpdate = iv_.lastUpdate;
    }

    /// @inheritdoc IMarketOracle
    function getRiskFreeRate(address token0) external view returns (uint256 rate) {
        OracleValue storage rfr_ = _riskFreeRate[token0];

        if (rfr_.lastUpdate == 0) {
            // NOTE: it's up to the deployer to set the right values; this is just a safe last resort.
            return 0.03e18;
        }

        rate = rfr_.value;
    }

    function setRiskFreeRate(address token0, uint256 value) public {
        _checkRole(ROLE_ADMIN);
        if (value > 0.25e18) {
            revert OutOfAllowedRange();
        }

        OracleValue storage rfr_ = _riskFreeRate[token0];

        uint256 old = rfr_.value;
        rfr_.value = value;
        rfr_.lastUpdate = block.timestamp;

        emit ChangedRFR(token0, value, old);
    }

    function getRiskFreeRateLastUpdate(address token0) external view returns (uint256 lastUpdate) {
        OracleValue storage rfr_ = _riskFreeRate[token0];
        lastUpdate = rfr_.lastUpdate;
    }
}
