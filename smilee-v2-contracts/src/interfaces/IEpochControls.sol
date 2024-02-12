// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Epoch} from "../lib/EpochController.sol";

/**
    @title A base contract for rolling epochs
 */
interface IEpochControls {
    /**
        @notice Returns the current epoch status
     */
    function getEpoch() external view returns (Epoch memory);

    /**
        @notice Regenerates the epoch-related processes, moving the current epoch to the next one
    */
    function rollEpoch() external;
}
