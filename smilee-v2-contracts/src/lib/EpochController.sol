// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EpochFrequency} from "./EpochFrequency.sol";

struct Epoch {
    uint256 current;
    uint256 previous;
    uint256 frequency;
    uint256 numberOfRolledEpochs;
    uint256 firstEpochTimespan;
}

library EpochController {
    error EpochFinished();
    error EpochNotFinished();

    function init(Epoch storage epoch, uint256 epochFrequency, uint256 firstEpochTimespan) external {
        EpochFrequency.validityCheck(epochFrequency);
        EpochFrequency.validityCheck(firstEpochTimespan);

        epoch.firstEpochTimespan = firstEpochTimespan;
        epoch.current = _getNextExpiry(block.timestamp, epoch.firstEpochTimespan);
        epoch.previous = 0;
        epoch.frequency = epochFrequency;
        epoch.numberOfRolledEpochs = 0;
    }

    function roll(Epoch storage epoch) external {
        epoch.previous = epoch.current;
        epoch.current = _getNextExpiry(epoch.current, epoch.frequency);
        epoch.numberOfRolledEpochs++;
    }

    function _getNextExpiry(uint256 from, uint256 timespan) private view returns (uint256 nextExpiry) {
        // NOTE: the next expiry may be less than `timespan` seconds in the future
        //       as it's computed from the reference timestamp.
        //       Client contracts SHOULD NOT request it within the end of such time windows.
        //       As this function is called within `init`, the developers MUST pay attention
        //       when they deploy their contracts.
        nextExpiry = EpochFrequency.nextExpiry(from, timespan);

        // If next epoch expiry is in the past go to next of the next
        // IDEA: store and update the reference timestamp within the epoch struct in order to save gas
        while (block.timestamp > nextExpiry) {
            nextExpiry = EpochFrequency.nextExpiry(nextExpiry, timespan);
        }
    }

    /**
        @notice Check if an epoch should be considered ended
        @param epoch The epoch to check
        @return True if epoch is finished, false otherwise
        @dev it is expected to receive epochs that are <= currentEpoch
     */
    function isFinished(Epoch memory epoch) public view returns (bool) {
        return block.timestamp > epoch.current;
    }

    function timeToNextEpoch(Epoch calldata epoch) external view returns (uint256) {
        if (isFinished(epoch)) {
            return 0;
        }

        return epoch.current - block.timestamp;
    }
}
