// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

struct TimeLockedAddress {
    address safe;
    address proposed;
    uint256 validFrom;
}

struct TimeLockedUInt {
    uint256 safe;
    uint256 proposed;
    uint256 validFrom;
}

struct TimeLockedBool {
    bool safe;
    bool proposed;
    uint256 validFrom;
}

struct TimeLockedBytes {
    bytes safe;
    bytes proposed;
    uint256 validFrom;
}

library TimeLock {
    //-------------------------------------------------------------------------
    // Address
    //-------------------------------------------------------------------------

    function set(TimeLockedAddress storage tl, address value, uint256 delay) external {
        if (tl.validFrom == 0) {
            // The very first call is expected to be safe for immediate usage
            // NOTE: its security is linked to the deployment script
            tl.safe = value;
        }
        if (tl.validFrom > 0 && block.timestamp >= tl.validFrom) {
            tl.safe = tl.proposed;
        }
        tl.proposed = value;
        tl.validFrom = block.timestamp + delay;
    }

    function get(TimeLockedAddress calldata tl) external view returns (address) {
        if (block.timestamp < tl.validFrom) {
            return tl.safe;
        } else {
            return tl.proposed;
        }
    }

    //-------------------------------------------------------------------------
    // UInt256
    //-------------------------------------------------------------------------

    function set(TimeLockedUInt storage tl, uint256 value, uint256 delay) external {
        if (tl.validFrom == 0) {
            // The very first call is expected to be safe for immediate usage
            // NOTE: its security is linked to the deployment script
            tl.safe = value;
        }
        if (tl.validFrom > 0 && block.timestamp >= tl.validFrom) {
            tl.safe = tl.proposed;
        }
        tl.proposed = value;
        tl.validFrom = block.timestamp + delay;
    }

    function get(TimeLockedUInt calldata tl) external view returns (uint256) {
        if (block.timestamp < tl.validFrom) {
            return tl.safe;
        } else {
            return tl.proposed;
        }
    }

    //-------------------------------------------------------------------------
    // Bool
    //-------------------------------------------------------------------------

    function set(TimeLockedBool storage tl, bool value, uint256 delay) external {
        if (tl.validFrom == 0) {
            // The very first call is expected to be safe for immediate usage
            // NOTE: its security is linked to the deployment script
            tl.safe = value;
        }
        if (tl.validFrom > 0 && block.timestamp >= tl.validFrom) {
            tl.safe = tl.proposed;
        }
        tl.proposed = value;
        tl.validFrom = block.timestamp + delay;
    }

    function get(TimeLockedBool calldata tl) external view returns (bool) {
        if (block.timestamp < tl.validFrom) {
            return tl.safe;
        } else {
            return tl.proposed;
        }
    }

    //-------------------------------------------------------------------------
    // Bytes
    //-------------------------------------------------------------------------

    function set(TimeLockedBytes storage tl, bytes memory value, uint256 delay) external {
        if (tl.validFrom == 0) {
            // The very first call is expected to be safe for immediate usage
            // NOTE: its security is linked to the deployment script
            tl.safe = value;
        }
        if (tl.validFrom > 0 && block.timestamp >= tl.validFrom) {
            tl.safe = tl.proposed;
        }
        tl.proposed = value;
        tl.validFrom = block.timestamp + delay;
    }

    function get(TimeLockedBytes calldata tl) external view returns (bytes memory) {
        if (block.timestamp < tl.validFrom) {
            return tl.safe;
        } else {
            return tl.proposed;
        }
    }
}
