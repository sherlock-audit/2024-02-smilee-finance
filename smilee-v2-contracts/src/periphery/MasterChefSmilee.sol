// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {UD60x18, ud, convert} from "@prb/math/UD60x18.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {IRewarder} from "../interfaces/IRewarder.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IMasterChefSmilee} from "../interfaces/IMasterChefSmilee.sol";

/**
    @title Single entry point for stake positions creation.
 */
contract MasterChefSmilee is Ownable, IMasterChefSmilee {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    struct VaultInfo {
        // How many allocation points assigned to this pool. Tokens to distribute per second.
        uint256 allocPoint;
        uint256 lastRewardTimestamp;
        uint256 accSmileePerShare;
        IRewarder rewarder;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 rewardCollect;
    }

    ERC20 public rewardToken;
    IAddressProvider public addressProvider;
    uint256 public smileePerSec;
    uint256 public startTimestamp;
    uint256 public totalStaked;
    uint256 public totalAllocPoint;
    uint256 public rewardSupply;

    EnumerableSet.AddressSet internal _vaults;
    /// @dev vault address -> vault info
    mapping(address => VaultInfo) public vaultInfo;
    /// @dev vault address -> user address -> Info
    mapping(address => mapping(address => UserInfo)) public userStakeInfo;

    error AmountZero();
    error ExceedsAvailable();
    error StakeToNonVaultContract();
    error RewardNotZeroOrContract();
    error AlreadyRegisteredVault();

    event Add(address indexed vault, uint256 allocPoint);
    event Set(address indexed vault, uint256 allocPoint);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Harvest(address indexed user, address vault, uint256 reward);
    event UpdateVault(
        address indexed vault,
        uint256 lastRewardTimestamp,
        uint256 sharesSupply,
        uint256 accSmileePerShare
    );
    event EmergencyWithdraw(address indexed user, address vault, uint256 amount);

    constructor(uint256 _smileePerSec, uint256 _startTimestamp, IAddressProvider _addressProvider) Ownable() {
        smileePerSec = _smileePerSec;
        startTimestamp = _startTimestamp;
        addressProvider = _addressProvider;
        totalAllocPoint = 0;
    }

    function _isVault(address _vault) internal view {
        // Check if provided address is a valid vault
        IRegistry registry = IRegistry(IAddressProvider(addressProvider).registry());
        if (!registry.isRegisteredVault(_vault)) {
            revert StakeToNonVaultContract();
        }
    }

    function _isValidRewarder(address _rewarder) internal view {
        // Check if provided address is a valid contract
        if (!(Address.isContract(_rewarder) || _rewarder == address(0))) {
            revert RewardNotZeroOrContract();
        }
    }

    /// @inheritdoc IMasterChefSmilee
    function add(address _vault, uint256 _allocPoint, IRewarder _rewarder) public onlyOwner {
        _isVault(_vault);
        if (_vaults.contains(_vault)) {
            revert AlreadyRegisteredVault();
        }
        _isValidRewarder(address(_rewarder));

        massUpdateVaults();
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = ud(totalAllocPoint).add(convert(_allocPoint)).unwrap();

        VaultInfo storage _vaultInfo = vaultInfo[_vault];
        _vaultInfo.allocPoint = _allocPoint;
        _vaultInfo.lastRewardTimestamp = lastRewardTimestamp;
        _vaultInfo.accSmileePerShare = 0;
        _vaultInfo.rewarder = _rewarder;
        _vaults.add(_vault);
        emit Add(_vault, _allocPoint);
    }

    /// @inheritdoc IMasterChefSmilee
    function set(address _vault, uint256 _allocPoint, IRewarder _rewarder, bool overwrite) public onlyOwner {
        _isVault(_vault);
        massUpdateVaults();
        totalAllocPoint = ud(totalAllocPoint)
            .sub(convert(vaultInfo[_vault].allocPoint))
            .add(convert(_allocPoint))
            .unwrap();
        vaultInfo[_vault].allocPoint = _allocPoint;
        if (overwrite) {
            _isValidRewarder(address(_rewarder));
            vaultInfo[_vault].rewarder = _rewarder;
        }
        emit Set(_vault, _allocPoint);
    }

    function pendingTokens(
        address _vault,
        address _user
    )
        external
        view
        returns (
            uint256 pendingRewardToken,
            address bonusTokenAddress,
            /* string memory bonusTokenSymbol, */
            uint256 pendingBonusToken
        )
    {
        VaultInfo storage _vaultInfo = vaultInfo[_vault];
        UserInfo storage _userInfo = userStakeInfo[_vault][_user]; //msg.sender
        uint256 accSmileePerShare = _vaultInfo.accSmileePerShare;
        uint256 sharesSupply = IERC20(_vault).balanceOf(address(this));
        if (block.timestamp > _vaultInfo.lastRewardTimestamp && sharesSupply != 0) {
            UD60x18 multiplier = convert(block.timestamp).sub(convert(_vaultInfo.lastRewardTimestamp));
            uint256 smileeReward = multiplier
                .mul(convert(smileePerSec))
                .mul(convert(_vaultInfo.allocPoint))
                .div(ud(totalAllocPoint))
                .unwrap();
            accSmileePerShare = ud(accSmileePerShare).add(ud(smileeReward).div(convert(sharesSupply))).unwrap();
        }
        pendingRewardToken = ud(_userInfo.amount).mul(ud(accSmileePerShare)).sub(ud(_userInfo.rewardDebt)).unwrap();

        // If it's a double reward farm, we return info about the bonus token
        if (address(_vaultInfo.rewarder) != address(0)) {
            bonusTokenAddress = rewarderBonusTokenInfo(_vault);
            pendingBonusToken = _vaultInfo.rewarder.pendingTokens(_user);
        }
    }

    function massUpdateVaults() public {
        uint256 length = _vaults.length();
        for (uint256 vid = 0; vid < length; ++vid) {
            updateVault(_vaults.at(vid));
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updateVault(address _vault) public {
        VaultInfo storage _vaultInfo = vaultInfo[_vault];
        if (block.timestamp <= _vaultInfo.lastRewardTimestamp) {
            return;
        }

        uint256 sharesSupply = IERC20(_vault).balanceOf(address(this));
        if (sharesSupply == 0) {
            _vaultInfo.lastRewardTimestamp = block.timestamp;
            return;
        }

        UD60x18 multiplier = convert(block.timestamp).sub(convert(_vaultInfo.lastRewardTimestamp));
        uint256 smileeReward = multiplier
            .mul(convert(smileePerSec))
            .mul(convert(_vaultInfo.allocPoint))
            .div(ud(totalAllocPoint))
            .unwrap();
        // TODO: create dummy token
        // rewardToken.mint(address(this), smileeReward);
        rewardSupply = ud(rewardSupply).add(ud(smileeReward)).unwrap();
        _vaultInfo.accSmileePerShare = ud(_vaultInfo.accSmileePerShare)
            .add(ud(smileeReward).div(convert(sharesSupply)))
            .unwrap();
        _vaultInfo.lastRewardTimestamp = block.timestamp;
        emit UpdateVault(_vault, _vaultInfo.lastRewardTimestamp, sharesSupply, _vaultInfo.accSmileePerShare);
    }

    /// @inheritdoc IMasterChefSmilee
    function deposit(address _vault, uint256 _amount) public {
        _isVault(_vault);
        if (_amount == 0) {
            revert AmountZero();
        }

        VaultInfo storage _vaultInfo = vaultInfo[_vault];
        UserInfo storage _userInfo = userStakeInfo[_vault][msg.sender];

        updateVault(_vault);
        _userInfo.amount = ud(_userInfo.amount).add(convert(_amount)).unwrap();
        _userInfo.rewardDebt = ud(_userInfo.amount).mul(convert(_vaultInfo.accSmileePerShare)).div(ud(1e12)).unwrap();

        IRewarder rewarder = _vaultInfo.rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onSmileeReward(msg.sender, _userInfo.amount, false);
        }

        // Transfer tokens from user to contract
        IERC20(_vault).safeTransferFrom(msg.sender, address(this), _amount);

        totalStaked += _amount;

        // Emit stake event
        emit Staked(msg.sender, _amount);
    }

    /// @inheritdoc IMasterChefSmilee
    function withdraw(address _vault, uint256 _amount) public {
        _isVault(_vault);
        VaultInfo storage _vaultInfo = vaultInfo[_vault];
        UserInfo storage _userInfo = userStakeInfo[_vault][msg.sender];

        if (_userInfo.amount < convert(_amount).unwrap()) {
            revert ExceedsAvailable();
        }
        updateVault(_vault);

        uint256 pending = ud(_userInfo.amount)
            .mul(ud(_vaultInfo.accSmileePerShare))
            .sub(ud(_userInfo.rewardDebt))
            .unwrap();
        _safeSmileeTransfer(_vault, msg.sender, pending); // Harvest reward token

        IRewarder _rewarder = _vaultInfo.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onSmileeReward(msg.sender, _userInfo.amount, true);
        }

        emit Harvest(msg.sender, _vault, pending);

        _userInfo.amount = ud(_userInfo.amount).sub(convert(_amount)).unwrap();
        _userInfo.rewardDebt = ud(_userInfo.amount).mul(ud(_vaultInfo.accSmileePerShare)).unwrap();
        totalStaked -= _amount;

        IERC20(_vault).safeTransfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    /**
        @notice Harvest proceeds for transaction sender to `to`.
        @param _vault The index of the pool. See `poolInfo`.
     */
    function harvest(address _vault) public {
        VaultInfo storage _vaultInfo = vaultInfo[_vault];
        UserInfo storage _userInfo = userStakeInfo[_vault][msg.sender];
        updateVault(_vault);

        uint256 accumulatedSmilee = ud(_userInfo.amount).mul(ud(_vaultInfo.accSmileePerShare)).unwrap();
        uint256 pending = ud(accumulatedSmilee).sub(ud(_userInfo.rewardDebt)).unwrap();
        _safeSmileeTransfer(_vault, msg.sender, pending);

        _userInfo.rewardDebt = accumulatedSmilee;

        IRewarder _rewarder = _vaultInfo.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onSmileeReward(msg.sender, _userInfo.amount, true);
        }

        emit Harvest(msg.sender, _vault, pending);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(address _vault) public {
        VaultInfo storage _vaultInfo = vaultInfo[_vault];
        UserInfo storage _userInfo = userStakeInfo[_vault][msg.sender];

        _userInfo.amount = 0;
        _userInfo.rewardDebt = 0;

        IRewarder _rewarder = _vaultInfo.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onSmileeReward(msg.sender, 0, false);
        }

        IERC20(_vault).safeTransfer(address(msg.sender), _userInfo.amount);
        emit EmergencyWithdraw(msg.sender, _vault, _userInfo.amount);
    }

    function _safeSmileeTransfer(address _vault, address _to, uint256 _amount) internal {
        // uint256 smileeBalance = rewardToken.balanceOf(address(this));
        // if (_amount > smileeBalance) {
        //     rewardToken.transfer(_to, smileeBalance);
        // } else {
        //     rewardToken.transfer(_to, _amount);
        // }

        UserInfo storage _userInfo = userStakeInfo[_vault][_to];
        if (_amount > rewardSupply) {
            _userInfo.rewardCollect = ud(_userInfo.rewardCollect).add(ud(rewardSupply)).unwrap();
            rewardSupply = 0;
        } else {
            _userInfo.rewardCollect = ud(_userInfo.rewardCollect).add(ud(_amount)).unwrap();
            rewardSupply = ud(rewardSupply).sub(ud(_amount)).unwrap();
        }
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    function vaultLength() external view returns (uint256) {
        return _vaults.length();
    }

    function getVaultInfo(address _vault) external view returns (VaultInfo memory vault) {
        vault = vaultInfo[_vault];
    }

    // Get bonus token info from the rewarder contract for a given pool, if it is a double reward farm
    function rewarderBonusTokenInfo(address _vault) public view returns (address bonusTokenAddress) {
        VaultInfo storage _vaultInfo = vaultInfo[_vault];
        if (address(_vaultInfo.rewarder) != address(0)) {
            bonusTokenAddress = address(_vaultInfo.rewarder.rewardToken());
        }
    }
}
