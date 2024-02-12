// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IEpochControls} from "./interfaces/IEpochControls.sol";
import {Epoch, EpochController} from "./lib/EpochController.sol";

abstract contract EpochControls is IEpochControls {
    using EpochController for Epoch;

    Epoch private _epoch;

    event EpochRolled(uint256 previousEpoch, uint256 currentEpoch);

    constructor(uint256 epochFrequency, uint256 firstEpochTimespan) {
        _epoch.init(epochFrequency, firstEpochTimespan);
    }

    /// @inheritdoc IEpochControls
    function getEpoch() public view returns (Epoch memory) {
        return _epoch;
    }

    /// @inheritdoc IEpochControls
    function rollEpoch() external virtual override {
        _checkEpochFinished();

        _beforeRollEpoch();
        _epoch.roll();
        _afterRollEpoch();

        emit EpochRolled(_epoch.previous, _epoch.current);
    }

    /// @notice Hook that is called before rolling the epoch
    function _beforeRollEpoch() internal virtual {}

    /// @notice Hook that is called after rolling the epoch.
    function _afterRollEpoch() internal virtual {}

    /// @notice Ensures that the current epoch is not concluded
    function _checkEpochNotFinished() internal view {
        if (_epoch.isFinished()) {
            revert EpochController.EpochFinished();
        }
    }

    /// @notice Ensures that the current epoch is concluded
    function _checkEpochFinished() internal view {
        if (!_epoch.isFinished()) {
            revert EpochController.EpochNotFinished();
        }
    }
}
