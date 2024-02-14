// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRewarder} from "../interfaces/IRewarder.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";

interface IMasterChefSmilee {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct VaultInfo {
        // How many allocation points assigned to this pool. Tokens to distribute per second.
        uint256 allocPoint;
        uint256 lastRewardTimestamp;
        uint256 accSmileePerShare;
    }

    function vaultInfo(uint256 _vault) external view returns (VaultInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function deposit(uint256 _vault, uint256 _amount) external;
}

/**
 * This is a sample contract to be used in the MasterChefSmilee contract for partners to reward
 * stakers with their native token.
 *
 * It assumes no minting rights, so requires a set amount of YOUR_TOKEN to be transferred to this contract prior.
 * E.g. say you've allocated 100,000 XYZ to the JOE-XYZ farm over 30 days. Then you would need to transfer
 * 100,000 XYZ and set the block reward accordingly so it's fully distributed after 30 days.
 *
 *
 * Issue with the previous version is that this fraction, `tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply)`,
 * can return 0 or be very inacurate with some tokens:
 *      uint256 timeElapsed = block.timestamp.sub(vault.lastRewardTimestamp);
 *      uint256 tokenReward = timeElapsed.mul(tokenPerSec);
 *      accTokenPerShare = accTokenPerShare.add(
 *          tokenReward.mul(ACC_TOKEN_PRECISION).div(lpSupply)
 *      );
 *  The goal is to set ACC_TOKEN_PRECISION high enough to prevent this without causing overflow too.
 */
contract SimpleRewarderPerSec is IRewarder, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Info of each mcSmilee user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of YOUR_TOKEN entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each mcSmilee poolInfo.
    /// `accTokenPerShare` Amount of YOUR_TOKEN each LP token is worth.
    /// `lastRewardTimestamp` The last timestamp YOUR_TOKEN was rewarded to the poolInfo.
    struct VaultInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardTimestamp;
    }

    IERC20 public immutable override rewardToken;
    bool public immutable isNative;
    IMasterChefSmilee public immutable mcSmilee;
    uint256 public tokenPerSec;

    // Given the fraction, tokenReward * ACC_TOKEN_PRECISION / sharesSupply, we consider
    // several edge cases.
    //
    // Edge case n1: maximize the numerator, minimize the denominator.
    // `sharesSupply` = 1 WEI
    // `tokenPerSec` = 1e(30)
    // `timeElapsed` = 31 years, i.e. 1e9 seconds
    // result = 1e9 * 1e30 * 1e36 / 1
    //        = 1e75
    // (No overflow as max uint256 is 1.15e77).
    // PS: This will overflow when `timeElapsed` becomes greater than 1e11, i.e. in more than 3_000 years
    // so it should be fine.
    //
    // Edge case n2: minimize the numerator, maximize the denominator.
    // `sharesSupply` = max(uint112) = 1e34
    // `tokenPerSec` = 1 WEI
    // `timeElapsed` = 1 second
    // result = 1 * 1 * 1e36 / 1e34
    //        = 1e2
    // (Not rounded to zero, therefore ACC_TOKEN_PRECISION = 1e36 is safe)
    uint256 private constant _ACC_TOKEN_PRECISION = 1e36;

    /// @notice Info of the vaultInfo.
    VaultInfo public vaultInfo;
    /// @notice Info of each user that stakes vault shares
    mapping(address => UserInfo) public userInfo;

    event OnReward(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    modifier onlyMCS() {
        require(msg.sender == address(mcSmilee), "onlyMCS: only MasterChefSmilee can call this function");
        _;
    }

    constructor(
        IERC20 _rewardToken,
        uint256 _tokenPerSec,
        IMasterChefSmilee _mcSmilee,
        bool _isNative
    ) Ownable() {
        require(Address.isContract(address(_rewardToken)), "constructor: reward token must be a valid contract");
        require(Address.isContract(address(_mcSmilee)), "constructor: MasterChefJoe must be a valid contract");
        require(_tokenPerSec <= 1e30, "constructor: token per seconds can't be greater than 1e30");

        rewardToken = _rewardToken;
        tokenPerSec = _tokenPerSec;
        mcSmilee = _mcSmilee;
        isNative = _isNative;
        vaultInfo = VaultInfo({lastRewardTimestamp: block.timestamp, accTokenPerShare: 0});
    }

    /// @notice payable function needed to receive ARB
    receive() external payable {
        require(isNative, "Non native rewarder");
    }

    /// @inheritdoc IRewarder
    function onSmileeReward(address _user, uint256 _amount, bool harvest) external override onlyMCS nonReentrant {
        updateVault();

        uint256 accTokenPerShare = vaultInfo.accTokenPerShare;
        UserInfo storage user = userInfo[_user];

        uint256 pending = user.unpaidRewards;
        uint256 userAmount = user.amount;

        if ((userAmount > 0 || pending > 0) && harvest) {
            pending = (ud(userAmount).mul(ud(accTokenPerShare)).div(ud(_ACC_TOKEN_PRECISION)))
                .sub(ud(user.rewardDebt))
                .add(ud(pending))
                .unwrap();

            if (pending > 0) {
                if (isNative) {
                    uint256 _balance = address(this).balance;

                    if (_balance > 0) {
                        if (pending > _balance) {
                            (bool success, ) = _user.call{value:_balance}("");
                            require(success, "Transfer failed");
                            user.unpaidRewards = pending - _balance;
                        } else {
                            (bool success, ) = _user.call{value:_balance}("");
                            require(success, "Transfer failed");
                            user.unpaidRewards = 0;
                        }
                    }
                } else {
                    uint256 _balance = rewardToken.balanceOf(address(this));

                    if (_balance > 0) {
                        if (pending > _balance) {
                            rewardToken.safeTransfer(_user, _balance);
                            user.unpaidRewards = pending - _balance;
                        } else {
                            rewardToken.safeTransfer(_user, pending);
                            user.unpaidRewards = 0;
                        }
                    }
                }
            }
        }

        user.amount = _amount;
        user.rewardDebt = ud(_amount).mul(ud(accTokenPerShare)).div(ud(_ACC_TOKEN_PRECISION)).unwrap();
        emit OnReward(_user, pending - user.unpaidRewards);
    }

    /// @inheritdoc IRewarder
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        VaultInfo memory vault = vaultInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = vault.accTokenPerShare;
        uint256 sharesSupply = rewardToken.balanceOf(address(mcSmilee));

        if (block.timestamp > vault.lastRewardTimestamp && sharesSupply != 0) {
            UD60x18 timeElapsed = ud(block.timestamp).sub(ud(vault.lastRewardTimestamp));
            UD60x18 tokenReward = timeElapsed.mul(ud(tokenPerSec));
            accTokenPerShare = ud(accTokenPerShare)
                .add(tokenReward.mul(ud(_ACC_TOKEN_PRECISION)).div(ud(sharesSupply)))
                .unwrap();
        }

        pending = (ud(user.amount).mul(ud(accTokenPerShare)).div(ud(_ACC_TOKEN_PRECISION)))
            .sub(ud(user.rewardDebt))
            .add(ud(user.unpaidRewards))
            .unwrap();
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        if (isNative) {
            return address(this).balance;
        } else {
            return rewardToken.balanceOf(address(this));
        }
    }

    /**
        @notice Sets the distribution reward rate. This will also update the vaultInfo.
        @param _tokenPerSec The number of tokens to distribute per second
     */
    function setRewardRate(uint256 _tokenPerSec) external onlyOwner {
        updateVault();

        uint256 oldRate = tokenPerSec;
        tokenPerSec = _tokenPerSec;

        emit RewardRateUpdated(oldRate, _tokenPerSec);
    }

    /**
        @notice Update reward variables of the given vaultInfo.
     */
    function updateVault() public {
        VaultInfo memory vault = vaultInfo;

        if (block.timestamp > vault.lastRewardTimestamp) {
            uint256 sharesSupply = rewardToken.balanceOf(address(mcSmilee));

            if (sharesSupply > 0) {
                UD60x18 timeElapsed = ud(block.timestamp).sub(ud(vault.lastRewardTimestamp));
                UD60x18 tokenReward = timeElapsed.mul(ud(tokenPerSec));
                vault.accTokenPerShare = ud(vault.accTokenPerShare)
                    .add((tokenReward.mul(ud(_ACC_TOKEN_PRECISION)).div(ud(sharesSupply))))
                    .unwrap();
            }

            vault.lastRewardTimestamp = block.timestamp;
            vaultInfo = vault;
        }
    }

    /// @notice In case rewarder is stopped before emissions finished, this function allows
    /// withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        if (isNative) {
            (bool success, ) = msg.sender.call{value:(address(this).balance)}("");
            require(success, "Transfer failed");
        } else {
            rewardToken.safeTransfer(address(msg.sender), rewardToken.balanceOf(address(this)));
        }
    }
}
