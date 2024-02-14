// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExchange} from "../../src/interfaces/IExchange.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";
import {Vault} from "../../src/Vault.sol";

/**
    @notice Vault with manually managed liquidity, to ease testing of DVPs
    Such vault should allow the test to simulate the presence of enough liquidity for the DVP operations.
 */
contract MockedVault is Vault {
    bool internal _fakeV0;
    uint256 internal _v0;

    constructor(
        address baseToken_,
        address sideToken_,
        uint256 epochFrequency_,
        address addressProvider_
    ) Vault(baseToken_, sideToken_, epochFrequency_, epochFrequency_, addressProvider_) {
        _hedgeMargin = 0;
    }

    function setV0(uint256 value) public {
        _v0 = value;
        _fakeV0 = true;
    }

    function deltaHedgeMock(int256 delta) public {
        _deltaHedge(delta);
    }

    function useRealV0() public {
        _fakeV0 = false;
    }

    /// @dev Overwrite real v0 with the value of manually managed `_v0`
    function v0() public view override returns (uint256) {
        if (_fakeV0) {
            return _v0;
        }
        return super.v0();
    }

    /// @dev Expose address provider
    function addressProvider() external view returns (address) {
        return address(_addressProvider);
    }

    /// @notice Increases or decreases underlying portfolio value by the given percentage
    function moveValue(int256 percentage) public {
        // percentage
        // 10000 := 100%
        // 100 := 1%
        // revert if <= 100 %
        require(percentage >= -10000);

        uint256 sideTokens = IERC20(sideToken).balanceOf(address(this));
        _sellSideTokens(sideTokens);

        int256 baseDelta = (int(_notionalBaseTokens()) * percentage) / 10000;
        _moveToken(baseToken, baseDelta, false);

        address exchangeAddress = _addressProvider.exchangeAdapter();
        IExchange exchange = IExchange(exchangeAddress);

        // Equal weight rebalance:
        sideTokens = IERC20(sideToken).balanceOf(address(this));
        uint256 halfNotional = notional() / 2;
        uint256 targetSideTokens = exchange.getOutputAmount(baseToken, sideToken, halfNotional);
        _deltaHedge(int256(targetSideTokens) - int256(sideTokens));

        // _equalWeightRebalance();
    }

    // function equalWeightRebalance() external {
    //     _equalWeightRebalance();
    // }

    function notionalBaseTokens() public view returns (uint256) {
        return _notionalBaseTokens();
    }

    function moveBaseToken(int amount) public {
        _moveToken(baseToken, amount, true);
    }

    /// @notice Gets or gives an amount of token from/to the sender, for testing purposes
    function _moveToken(address token, int256 amount, bool ignoreBaseTokenCheck) internal {
        if (amount > 0) {
            IERC20(token).transferFrom(msg.sender, address(this), uint256(amount));
        } else {
            uint256 absAmount = uint256(-amount);
            if (!ignoreBaseTokenCheck && token == baseToken && absAmount > _notionalBaseTokens()) {
                revert ExceedsAvailable();
            }
            IERC20(token).transfer(msg.sender, absAmount);
        }
    }

    function currentEpoch() external view returns (uint256) {
        return getEpoch().current;
    }

    function _beforeRollEpoch() internal virtual override {
        super._beforeRollEpoch();

        (uint256 baseTokens, ) = _tokenBalances();

        if (baseTokens < _state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs) {
            revert InsufficientLiquidity(
                bytes4(
                    keccak256(
                        "_beforeRollEpoch()::_state.liquidity.pendingWithdrawals + _state.liquidity.pendingPayoffs - baseTokens"
                    )
                )
            );
        }
    }
}
