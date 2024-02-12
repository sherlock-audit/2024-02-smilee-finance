// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    /**
        @notice Function called by MasterChefSmilee whenever staker claims token harvest.
                Allows staker to also receive a 2nd reward token.
        @param _user Address of user
        @param _amount Number of LP tokens the user has
        @param harvest Flag to send reward to user or not
     */
    function onSmileeReward(address _user, uint256 _amount, bool harvest) external;

    /**
        @notice View function to see pending tokens
        @param _user Address of user.
        @return pending reward for a given user.
     */
    function pendingTokens(address _user) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}
