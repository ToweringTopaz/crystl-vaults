// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/*
Join us at PolyCrystal.Finance!

█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/ABDKMath64x64.sol";

contract RevSharePool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint128 amount;     // How many LP tokens the user has provided.
        uint128 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    IERC20 public immutable lpToken;           // Address of LP token contract.

    // The stake token
    IERC20 public immutable WNATIVE;

    uint64 public lastRewardTime;  // Last timestamp that Rewards distribution occurred.

    // Half of the rewards will be distributed over this period
    uint64 public rewardHalflife;

    uint256 public accRewardPerShare; // Accumulated Rewards per share, times 1e30. See below.

    //All rewards which are earned by depositors but not yet harvested
    uint128 public rewardsPending;

    // Keep track of number of tokens staked in case the contract receives an improper transfer
    uint128 public totalStaked;

    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event DepositRewards(uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event SkimStakeTokenFees(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 rewardHalflife);
    event EmergencyRewardWithdraw(address indexed user, uint256 amount);
    event EmergencySweepWithdraw(address indexed user, IERC20 indexed token, uint256 amount);

    constructor(
        IERC20 _stakeToken,
        IERC20 _wnative,
        uint64 _rewardHalflife,
        uint64 _startTime
    ) 
    {
        WNATIVE = _wnative;
        rewardHalflife = _rewardHalflife;

        lpToken = _stakeToken;
        lastRewardTime = _startTime;

    }

    function decayHalflife(uint128 amountStart, uint64 timeLastUpdate, uint64 halflife) internal view returns (uint128 amountAfter, uint128 amountDecayed) {

        if (timeLastUpdate >= block.timestamp) return (amountStart, 0);

        amountAfter = uint128(ABDKMath64x64.div(
            ABDKMath64x64.fromUInt(amountStart),
            ABDKMath64x64.exp_2(
                ABDKMath64x64.divu(
                    block.timestamp - timeLastUpdate,
                    halflife
                )
            )
        ));
        amountDecayed = amountStart - amountAfter;
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTime && totalStaked != 0) {
            (,uint256 tokenReward) = decayHalflife(uint128(address(this).balance - rewardsPending), lastRewardTime, rewardHalflife);
            _accRewardPerShare += tokenReward * 1e30 / totalStaked;
        }
        return user.amount * _accRewardPerShare / 1e30 - user.rewardDebt;
    }

    function updatePool() external nonReentrant {
        _updatePool();
    }

    // Update reward variables of the given pool to be up-to-date.
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTime) {
            return;
        }
        if (totalStaked == 0) {
            lastRewardTime = uint64(block.timestamp);
            return;
        }
        (,uint128 tokenReward) = decayHalflife(uint128(address(this).balance - rewardsPending), lastRewardTime, rewardHalflife);
        rewardsPending += tokenReward;
        accRewardPerShare += tokenReward * 1e30 / totalStaked;
        lastRewardTime = uint64(block.timestamp);
    }


    /// Deposit staking token into the contract to earn rewards.
    /// @dev Since this contract needs to be supplied with rewards we are
    ///  sending the balance of the contract if the pending rewards are higher
    /// @param _amount The amount of staking tokens to deposit
    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint128 finalDepositAmount = 0;
        _updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount * accRewardPerShare / 1e30 - user.rewardDebt;
            if(pending > 0) {
                uint256 currentRewardBalance = rewardBalance();
                if(currentRewardBalance > 0) {
                    safeTransferReward(msg.sender, pending > currentRewardBalance ? currentRewardBalance : pending);
                }
            }
        }
        if (_amount > 0) {
            uint128 preStakeBalance = uint128(lpToken.balanceOf(address(this)));
            lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            finalDepositAmount = uint128(lpToken.balanceOf(address(this))) - preStakeBalance;
            user.amount += finalDepositAmount;
            totalStaked += finalDepositAmount;
        }
        user.rewardDebt = uint128(user.amount * accRewardPerShare / 1e30);

        emit Deposit(msg.sender, finalDepositAmount);
    }

    /// Withdraw rewards and/or staked tokens. Pass a 0 amount to withdraw only rewards
    /// @param _amount The amount of staking tokens to withdraw
    function withdraw(uint128 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        _updatePool();
        uint256 pending = user.amount * accRewardPerShare / 1e30 - user.rewardDebt;
        if(pending > 0) {
            uint256 currentRewardBalance = rewardBalance();
            if(currentRewardBalance > 0) {
                safeTransferReward(msg.sender, pending > currentRewardBalance ? currentRewardBalance : pending);
            }
        }
        if(_amount > 0) {
            user.amount -= _amount;
            lpToken.safeTransfer(msg.sender, _amount);
            totalStaked = totalStaked - _amount;
        }

        user.rewardDebt = uint128(user.amount * accRewardPerShare / 1e30);

        emit Withdraw(msg.sender, _amount);
    }

    /// Obtain the reward balance of this contract
    /// @return wei balace of conract
    function rewardBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // Deposit Rewards into contract
    function depositRewards() public nonReentrant payable {
        require(msg.value > 0, 'Deposit value must be greater than 0.');
        rewardsPending += uint128(msg.value);
        _updatePool();
        rewardsPending -= uint128(msg.value);
        emit DepositRewards(msg.value);
    }

    receive() external payable nonReentrant {
        depositRewards();
    }

    /// @param _to address to send reward token to
    /// @param _amount value of reward token to transfer
    function safeTransferReward(address _to, uint256 _amount) internal {
        rewardsPending -= uint128(_amount);
        (bool success,) = _to.call{value: _amount}("");
        require(success, "Reward transfer failed");
    }

    /// @dev Obtain the stake balance of this contract
    function totalStakeTokenBalance() public view returns (uint256) {
        return lpToken.balanceOf(address(this));
    }

    /// @dev Obtain the stake token fees (if any) earned by reflect token
    function getStakeTokenFeeBalance() public view returns (uint256) {
        return lpToken.balanceOf(address(this)) - totalStaked;
    }

    /* Admin Functions */

    /// @param _rewardHalflife The time in seconds in which half of rewards will be paid out
    function setRewardHalflife(uint64 _rewardHalflife) external nonReentrant onlyOwner {
        _updatePool();
        rewardHalflife = _rewardHalflife;
        emit LogUpdatePool(_rewardHalflife);
    }

        /// @dev Remove excess stake tokens earned by reflect fees
    function skimStakeTokenFees() external nonReentrant onlyOwner {
        uint256 stakeTokenFeeBalance = getStakeTokenFeeBalance();
        lpToken.safeTransfer(msg.sender, stakeTokenFeeBalance);
        emit SkimStakeTokenFees(msg.sender, stakeTokenFeeBalance);
    }

    /* Emergency Functions */

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        lpToken.safeTransfer(msg.sender, user.amount);
        totalStaked = totalStaked - user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external nonReentrant onlyOwner {
        _updatePool();
        require(_amount <= address(this).balance - rewardsPending, 'not enough rewards');
        // Withdraw rewards
        (bool success,) = _to.call{value: _amount}("");
        require(success, "Reward transfer failed");
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    /// @notice A public function to sweep accidental BEP20 transfers to this contract.
    ///   Tokens are sent to owner
    /// @param token The address of the BEP20 token to sweep
    function sweepToken(IERC20 token) external nonReentrant onlyOwner {
        require(token != lpToken, "cannot sweep staked token");
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
        emit EmergencySweepWithdraw(msg.sender, token, balance);
    }

}