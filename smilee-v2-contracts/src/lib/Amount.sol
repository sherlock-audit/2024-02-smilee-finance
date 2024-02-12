// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @notice Represents a notional amount for two strategies (call & put)
struct Amount {
    uint256 up; // Call / Bull
    uint256 down; // Put / Bear
}

library AmountHelper {

    /**
        @notice Increase amount.
        @param amount the increased amount.
     */
    function increase(Amount storage self, Amount memory amount) external {
        self.up += amount.up;
        self.down += amount.down;
    }

    /**
        @notice Decrease amount.
        @param amount the decreased amount.
     */
    function decrease(Amount storage self, Amount memory amount) external {
        self.up -= amount.up;
        self.down -= amount.down;
    }

    /**
        @notice Set the raw values.
        @param up_ The up amount.
        @param down_ The down amount.
     */
    function setRaw(Amount storage self, uint256 up_, uint256 down_) external {
        self.up = up_;
        self.down = down_;
    }

    /**
        @notice Get the underlying values.
        @return up_ The up amount.
        @return down_ The down amount.
     */
    function getRaw(Amount memory self) external pure returns (uint256 up_, uint256 down_) {
        up_ = self.up;
        down_ = self.down;
    }

    /**
        @notice Get the sum of the underlying values.
        @return total_ The total amount.
     */
    function getTotal(Amount memory self) external pure returns (uint256 total_) {
        total_ = self.up + self.down;
    }
}
