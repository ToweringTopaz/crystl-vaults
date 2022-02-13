// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

/*
Join us at PolyCrystal.Finance!

█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IVaultHealer.sol";
import "./interfaces/IBoostPool.sol";
import "hardhat/console.sol";

contract BoostPool is IBoostPool, Initializable, Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct User {
        uint128 amount;     // How many LP tokens the user has provided.
        int128 rewardDebt; // Reward debt. See explanation below.
    }

    // The vaultHealer where the staking / want tokens all reside
    IVaultHealer public immutable VAULTHEALER;
    // This is the vid + (a unique identifier << 224)
    uint256 public BOOST_ID;
    // The reward token
    IERC20 public REWARD_TOKEN;

    // Reward tokens created per block.

    uint112 public rewardPerBlock;
    // Keep track of number of tokens staked
    uint112 public totalStaked;
    // The block number when Reward mining starts.
    uint32 public startBlock;
	// The block number when mining ends.
    uint32 public bonusEndBlock;
    // Last block number that Rewards distribution occurs.
    uint32 lastRewardBlock;

    // Info of each user that stakes LP tokens.
    mapping (address => User) public userInfo;

     // Accumulated Rewards per share, times 1e30
    uint256 accRewardTokenPerShare;
    uint256 rewardsPaid;


    event Deposit(address indexed user, uint256 amount);
    event DepositRewards(uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event SkimStakeTokenFees(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 bonusEndBlock, uint256 rewardPerBlock);
    event EmergencyRewardWithdraw(address indexed user, uint256 amount);
    event EmergencySweepWithdraw(address indexed user, IERC20 indexed token, uint256 amount);

    constructor(address _vaultHealer) {
        VAULTHEALER = IVaultHealer(_vaultHealer);
    }

    function initialize(address _owner, uint256 _boostID, bytes calldata initdata) external initializer {
        require(address(VAULTHEALER) == msg.sender, "Wrong vaulthealer for pool implementation");
        (
            address _rewardToken,
            uint112 _rewardPerBlock,
            uint32 _delayBlocks,
            uint32 _durationBlocks
        ) = abi.decode(initdata,(address,uint112,uint32,uint32));
        require(IERC20(_rewardToken).balanceOf(address(this)) >= _durationBlocks * rewardPerBlock, "Can't activate pool without sufficient rewards");
        BOOST_ID = _boostID;

        _transferOwnership(_owner);
        
        (IERC20 vaultWant,,,,,,) = IVaultHealer(msg.sender).vaultInfo(uint256(_boostID & type(uint224).max));
        require(address(vaultWant) != address(0), "bad want/strat for stake_token_vid");

        REWARD_TOKEN = IERC20(_rewardToken);

        rewardPerBlock = uint112(_rewardPerBlock);
        
        startBlock = uint32(block.number + _delayBlocks);
        bonusEndBlock = uint32(block.number + _durationBlocks);
        lastRewardBlock = uint32(startBlock);
    }

    modifier onlyVaultHealer {
        require(msg.sender == address(VAULTHEALER), "only callable by vaulthealer");
        _;
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

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        User storage user = userInfo[_user];
        uint256 _accRewardTokenPerShare = accRewardTokenPerShare;
        uint _lastRewardBlock = lastRewardBlock;
        uint _totalStaked = totalStaked;
        if (block.number > _lastRewardBlock && _totalStaked != 0) {
            uint256 multiplier = getMultiplier(_lastRewardBlock, block.number);
            uint256 tokenReward = multiplier * rewardPerBlock;
            _accRewardTokenPerShare += tokenReward * 1e30 / _totalStaked;
        }
        return calcPending(user, _accRewardTokenPerShare);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        uint256 _lastRewardBlock = lastRewardBlock;
        if (block.number > _lastRewardBlock) {
            uint256 _totalStaked = totalStaked;
            if (_totalStaked > 0) {
                uint256 multiplier = getMultiplier(_lastRewardBlock, block.number);
                uint256 tokenReward = multiplier * rewardPerBlock;
                accRewardTokenPerShare += tokenReward * 1e30 / _totalStaked;
            }
            lastRewardBlock = uint32(block.number);
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
                        rewardsPaid += currentRewardBalance;
                        pending -= currentRewardBalance;
                    } else {
                        safeTransferReward(_user, pending);
                        rewardsPaid += pending;
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

    function joinPool(address _user, uint112 _amount) external onlyVaultHealer {
        updatePool();
        User storage user = userInfo[_user];
        require (user.amount == 0, "user already is in pool");
        require (block.number < bonusEndBlock, "pool has ended");
        user.amount = _amount;
        totalStaked += _amount;
        updateRewardDebt(user, 0);
    }
    //Used in place of deposit/withdraw because nothing is actually stored here
    function notifyOnTransfer(address _from, address _to, uint112 _amount) external onlyVaultHealer returns (uint status) {
        updatePool();

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
    function setRewardPerBlock(uint112 _rewardPerBlock) external onlyOwner {
        uint oldRewardPerBlock = rewardPerBlock;
        uint _bonusEndBlock = bonusEndBlock;

        require(block.number > _bonusEndBlock || _rewardPerBlock > oldRewardPerBlock, "cannot reduce rewards while pool is active");
        require(REWARD_TOKEN.balanceOf(address(this)) + rewardsPaid >= (_bonusEndBlock - startBlock) * _rewardPerBlock, "Can't extend pool without sufficient rewards");
        updatePool();
        rewardPerBlock = uint64(_rewardPerBlock);
        emit LogUpdatePool(_bonusEndBlock, _rewardPerBlock);
    }

    /// @param  _bonusEndBlock The block when rewards will end
    function setBonusEndBlock(uint32 _bonusEndBlock) external onlyOwner {
        require(_bonusEndBlock > bonusEndBlock, 'new bonus end block must be greater than current');
        uint _rewardPerBlock = rewardPerBlock;
        require(REWARD_TOKEN.balanceOf(address(this)) + rewardsPaid >= (_bonusEndBlock - block.number) * _rewardPerBlock, "Can't extend pool without sufficient rewards");
        updatePool();

        if (bonusEndBlock < block.number) startBlock = uint32(block.number);
        bonusEndBlock = _bonusEndBlock;

        emit LogUpdatePool(_bonusEndBlock, _rewardPerBlock);
    }

    /* Emergency Functions */

    // Withdraw without caring about rewards. EMERGENCY ONLY.  
    function emergencyWithdraw(address _user) external onlyVaultHealer returns (bool success) {
        User storage user = userInfo[_user];
        totalStaked -= uint112(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(_user, user.amount);
        return true;
    }


    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= REWARD_TOKEN.balanceOf(address(this)), 'not enough rewards');
        uint _startBlock = startBlock;
        uint _bonusEndBlock = bonusEndBlock;
        require(
            REWARD_TOKEN.balanceOf(address(this)) + rewardsPaid - _amount >= (_bonusEndBlock - _startBlock) * rewardPerBlock 
            || block.number < _startBlock 
            || block.number >= _bonusEndBlock + 100000, "cannot remove rewards from active pool"
        );

        // Withdraw rewards
        safeTransferReward(msg.sender, _amount);
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    /// @notice A public function to sweep accidental BEP20 transfers to this contract.
    ///   Tokens are sent to owner
    /// @param token The address of the BEP20 token to sweep
    function sweepToken(IERC20 token) external onlyOwner {
        
        require(token != REWARD_TOKEN, "cannot sweep reward token");
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
        emit EmergencySweepWithdraw(msg.sender, token, balance);
    }

    //Standard reward debt calculation, but subtracting any delinquent pending rewards
    function updateRewardDebt(User storage user, uint pending) private {
        user.rewardDebt = int128(int(user.amount * accRewardTokenPerShare / 1e30) - int(pending));

    }

    function calcPending(User storage user, uint _accRewardTokenPerShare) private view returns (uint pending) {
        pending = user.amount * _accRewardTokenPerShare / 1e30;
        
        unchecked { //If rewardDebt is negative, underflow is desired here. This adds delinquent pending rewards back into the current total
            pending -= uint(int(user.rewardDebt));

        }
    }
}