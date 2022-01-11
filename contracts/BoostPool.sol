// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

/*
Join us at PolyCrystal.Finance!

█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

import {Ownable, SafeERC20} from "./libs/OpenZeppelin.sol";
import {IERC20, IStrategy, IVaultHealer, IBoostPool} from "./libs/Interfaces.sol";
import "hardhat/console.sol";

contract BoostPool is IBoostPool, Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct User {
        uint256 amount;     // How many LP tokens the user has provided.
        int256 rewardDebt; // Reward debt. See explanation below.
    }

    // The vaultHealer where the staking / want tokens all reside
    IVaultHealer public immutable VAULTHEALER;
    // The stake token
    uint256 public immutable STAKE_TOKEN_VID;
    // The reward token
    IERC20 public immutable REWARD_TOKEN;

    // Reward tokens created per block.
    uint256 public rewardPerBlock;
    // Keep track of number of tokens staked
    uint256 public totalStaked;

    // Info of each user that stakes LP tokens.
    mapping (address => User) public userInfo;
    // The block number when Reward mining starts.
    uint256 public startBlock;
	// The block number when mining ends.
    uint256 public bonusEndBlock;
    //The ID number used by the VaultHealer to identify this boost, among those with the same staked token
    uint256 public boostID;
    // Last block number that Rewards distribution occurs.
    uint256 lastRewardBlock;
     // Accumulated Rewards per share, times 1e30
    uint256 accRewardTokenPerShare;


    event Deposit(address indexed user, uint256 amount);
    event DepositRewards(uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event SkimStakeTokenFees(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 bonusEndBlock, uint256 rewardPerBlock);
    event EmergencyRewardWithdraw(address indexed user, uint256 amount);
    event EmergencySweepWithdraw(address indexed user, IERC20 indexed token, uint256 amount);

  constructor (
        address _vaultHealer,
        uint256 _stakeTokenVid,
        address _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    )
    {
        VAULTHEALER = IVaultHealer(_vaultHealer);
        
        STAKE_TOKEN_VID = _stakeTokenVid;
        (IERC20 vaultWant, IStrategy vaultStrat) = IVaultHealer(_vaultHealer).vaultInfo(_stakeTokenVid);
        require(address(vaultWant) != address(0) && address(vaultStrat) != address(0), "bad want/strat for stake_token_vid");
        
        REWARD_TOKEN = IERC20(_rewardToken);
        uint rewardTotalSupply = IERC20(_rewardToken).totalSupply();

        rewardPerBlock = _rewardPerBlock;
        
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        lastRewardBlock = _startBlock;

        require (block.number <= startBlock, "rewards cannot have already started");
        require(rewardTotalSupply > _rewardPerBlock * (_bonusEndBlock - _startBlock), "pool would reward more than total supply of rewardtoken!");

        boostID = type(uint).max; //will be set by VH
    }

    modifier onlyVaultHealer {
        require(msg.sender == address(VAULTHEALER), "only callable by vaulthealer");
        _;
    }

    function vaultHealerActivate(uint _boostID) external onlyVaultHealer {
        
        require(boostID == type(uint).max, "boost already active!");
        boostID = _boostID;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to - _from;
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock - _from;
        }
    }

    /// @param  _bonusEndBlock The block when rewards will end
    function setBonusEndBlock(uint256 _bonusEndBlock) external onlyOwner {
        require(_bonusEndBlock > bonusEndBlock, 'new bonus end block must be greater than current');
        bonusEndBlock = _bonusEndBlock;
        emit LogUpdatePool(bonusEndBlock, rewardPerBlock);
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        User storage user = userInfo[_user];
        uint256 _accRewardTokenPerShare = accRewardTokenPerShare;
        if (block.number > lastRewardBlock && totalStaked != 0) {
            uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
            uint256 tokenReward = multiplier * rewardPerBlock;
            _accRewardTokenPerShare += tokenReward * 1e30 / totalStaked;
        }
        return calcPending(user, _accRewardTokenPerShare);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        if (block.number > lastRewardBlock) {
            if (totalStaked > 0) {
                uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
                uint256 tokenReward = multiplier * rewardPerBlock;
                accRewardTokenPerShare += tokenReward * 1e30 / totalStaked;
            }
            lastRewardBlock = block.number;
        }
    }

    //Internal function to harvest rewards
    function _harvest(address _user) internal returns (uint pending) {
        User storage user = userInfo[_user];
        if (user.amount > 0) {
            pending = calcPending(user, accRewardTokenPerShare);
            if(pending > 0) {
                uint256 currentRewardBalance = REWARD_TOKEN.balanceOf(address(this));
                if(currentRewardBalance > 0) {
                    if(pending > currentRewardBalance) {
                        safeTransferReward(_user, currentRewardBalance);
                        pending -= currentRewardBalance;
                    } else {
                        safeTransferReward(_user, pending);
                        pending = 0;
                    }
                }
            }
        }
    }

    function harvest(address _user) external onlyVaultHealer {
        updatePool();
        uint pending = _harvest(_user);
        updateRewardDebt(userInfo[_user], pending);
    }

    function joinPool(address _user, uint _amount) external onlyVaultHealer {
        updatePool();
        User storage user = userInfo[_user];
        require (user.amount == 0, "user already is in pool");
        require (block.number < bonusEndBlock, "pool has ended");
        user.amount = _amount;
        totalStaked += _amount;
        updateRewardDebt(user, 0);
    }
    //Used in place of deposit/withdraw because nothing is actually stored here
    function notifyOnTransfer(address _from, address _to, uint _amount) external onlyVaultHealer returns (uint status) {
        updatePool();
        console.log("notify on transfer: ", _amount);

        //User remains "active" unless rewards have expired and there are no unpaid pending amounts
        //4: pool done, 2: to done; 1: from done
        status = block.number >= bonusEndBlock ? 4 : 0; //if rewards have ended, mark pool done

        if (_to != address(0)) {
            User storage user = userInfo[_to];
            uint pending = _harvest(_to);
            if (pending == 0 && status >= 4)
                status |= 2;
            totalStaked += _amount;
            user.amount += _amount;
            updateRewardDebt(user, pending);
            emit Deposit(_to, _amount);
        }
        if (_from != address(0)) {
            User storage user = userInfo[_from];
            uint pending = _harvest(_from);
            if (pending == 0 && status >= 4)
                status |= 1;
            totalStaked -= _amount;
            user.amount -= _amount;
            updateRewardDebt(user, pending);
            emit Withdraw(_from, _amount);
        }
    }

    // Deposit Rewards into contract
    function depositRewards(uint256 _amount) external {
        require(_amount > 0, 'Deposit value must be greater than 0.');
        REWARD_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        emit DepositRewards(_amount);
    }

    /// @param _to address to send reward token to
    /// @param _amount value of reward token to transfer
    function safeTransferReward(address _to, uint256 _amount) internal {
        REWARD_TOKEN.safeTransfer(_to, _amount);
    }

    /* Admin Functions */

    /// @param _rewardPerBlock The amount of reward tokens to be given per block
    function setRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        updatePool();
        rewardPerBlock = _rewardPerBlock;
        emit LogUpdatePool(bonusEndBlock, rewardPerBlock);
    }

    /* Emergency Functions */

    // Withdraw without caring about rewards. EMERGENCY ONLY.  
    function emergencyWithdraw(address _user) external onlyVaultHealer returns (bool success) {
        User storage user = userInfo[_user];
        totalStaked -= user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(_user, user.amount);
        return true;
    }


    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= REWARD_TOKEN.balanceOf(address(this)), 'not enough rewards');
        // Withdraw rewards
        safeTransferReward(msg.sender, _amount);
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    /// @notice A public function to sweep accidental BEP20 transfers to this contract.
    ///   Tokens are sent to owner
    /// @param token The address of the BEP20 token to sweep
    function sweepToken(IERC20 token) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
        emit EmergencySweepWithdraw(msg.sender, token, balance);
    }

    //Standard reward debt calculation, but subtracting any delinquent pending rewards
    function updateRewardDebt(User storage user, uint pending) private {
        user.rewardDebt = int(user.amount * accRewardTokenPerShare / 1e30) - int(pending);
    }

    function calcPending(User storage user, uint _accRewardTokenPerShare) private view returns (uint pending) {
        pending = user.amount * _accRewardTokenPerShare / 1e30;
        
        unchecked { //If rewardDebt is negative, underflow is desired here. This adds delinquent pending rewards back into the current total
            pending -= uint(user.rewardDebt);
        }
    }
}