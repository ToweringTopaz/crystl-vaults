// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

/*
Join us at PolyCrystal.Finance!

█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

import "./interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@prb/math/contracts/PRBMath.sol";
import "./libraries/MoneyBomb.sol";

contract RadioactiveRevShare is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    // Info of each user.
    struct UserInfo {
        uint128 amount;     // How many LP tokens the user has provided.
        uint128 rewardDebt; // Reward debt. See explanation below.
    }

    IERC20 public immutable lpToken;           // Address of LP token contract.

    IWETH public immutable WNATIVE;

    uint40 public lastRewardTime;  // Last timestamp that Rewards distribution occurred.

    // Half of the rewards will be distributed over this period
    uint40 public rewardHalflife;

    uint176 public accRewardPerShare; // Accumulated Rewards per share, times 1e30. See below.

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
	event Harvest(address indexed user, uint256 amount);
	
    constructor(
        IERC20 _stakeToken,
        IWETH _wnative,
        uint40 _rewardHalflife,
        uint40 _startTime
    ) 
    {
        WNATIVE = _wnative;
        rewardHalflife = _rewardHalflife;

        lpToken = _stakeToken;
        lastRewardTime = _startTime > block.timestamp ? _startTime : uint40(block.timestamp);

    }

    function decayHalflife(uint amountStart, uint timeElapsed, uint halflife) public pure returns (uint amountAfter, uint amountDecayed) {

		amountAfter = amountStart;

		//A halflife of zero here indicates zero decay activity (disabled pool)
		if (halflife > 0) {

			//perform simple halvings if possible, preventing overflow conditions
			if (amountAfter > 0 && timeElapsed >= halflife) {
				amountAfter >>= timeElapsed / halflife;
				timeElapsed %= halflife;
			}
			
			if (amountAfter > 0 && timeElapsed > 0) {
				amountAfter = amountAfter * 1e18 / PRBMath.exp2((timeElapsed << 64) / halflife);
			}
			amountDecayed = amountStart - amountAfter;
		}
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        if (block.timestamp > lastRewardTime && totalStaked != 0) {
            (,uint256 tokenReward) = decayHalflife(address(this).balance - rewardsPending, block.timestamp - lastRewardTime, rewardHalflife);
            _accRewardPerShare += tokenReward * 1e30 / totalStaked;
        }
        return user.amount * _accRewardPerShare / 1e30 - user.rewardDebt;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        _updatePool(rewardsPending);
    }

	modifier updateRewardDebt {
		_;
		UserInfo storage user = userInfo[msg.sender];
		user.rewardDebt = toUint128(uint256(user.amount) * accRewardPerShare / 1e30);
	}

    function _updatePool(uint _rewardsPending) internal {
        if (block.timestamp > lastRewardTime) {
            if (totalStaked > 0) {
                (,uint256 tokenReward) = decayHalflife(address(this).balance - _rewardsPending, block.timestamp - lastRewardTime, rewardHalflife);
                rewardsPending += toUint128(tokenReward);
                accRewardPerShare = toUint176(accRewardPerShare + tokenReward * 1e30 / totalStaked);
            }
            lastRewardTime = uint40(block.timestamp);
        }
    }

    function deposit(uint256 _amount) external { deposit(false, _amount); }
    function withdraw(uint256 _amount) external { withdraw(false, _amount); }

    /// Deposit staking token into the contract to earn rewards.
    /// @dev Since this contract needs to be supplied with rewards we are
    ///  sending the balance of the contract if the pending rewards are higher
    /// @param _amount The amount of staking tokens to deposit
    function deposit(bool _wrapReward, uint256 _amount) public updateRewardDebt {
		UserInfo storage user = _harvest(_wrapReward);
        if (_amount > 0) {
            lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            totalStaked = toUint128(totalStaked + _amount);
            user.amount = uint128(user.amount + _amount);
        }

        emit Deposit(msg.sender, _amount);
    }

    /// Withdraw rewards and/or staked tokens. Pass a 0 amount to withdraw only rewards
    /// @param _amount The amount of staking tokens to withdraw
    function withdraw(bool _wrapReward, uint256 _amount) public updateRewardDebt {
		UserInfo storage user = _harvest(_wrapReward);
		
        if (user.amount < _amount) {
            if (user.amount == 0) revert("RevSharePool: withdraw zero balance");
            _amount = user.amount; 
        }
        if(_amount > 0) {
            user.amount -= toUint128(_amount);
            lpToken.safeTransfer(msg.sender, _amount);
            totalStaked -= uint128(_amount);
        }

        emit Withdraw(msg.sender, _amount);
    }
	
	function harvest(bool _wrapReward) external updateRewardDebt {
		_harvest(_wrapReward);
	}
	
	function _harvest(bool _wrapReward) internal returns (UserInfo storage user) {
		updatePool();
		user = userInfo[msg.sender];
		uint256 pending = uint256(user.amount) * accRewardPerShare / 1e30 - user.rewardDebt;
		if(pending > 0) {
			uint256 currentRewardBalance = rewardBalance();
			if(currentRewardBalance > 0) {
				safeTransferReward(_wrapReward, msg.sender, pending > currentRewardBalance ? currentRewardBalance : pending);
			}
		}
		emit Harvest(msg.sender, pending);
	}

    /// Obtain the reward balance of this contract
    /// @return wei balace of conract
    function rewardBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // Deposit Rewards into contract
    function depositRewards() public payable {
        _updatePool(rewardsPending + msg.value); //excludes the newly deposited rewards from the decay-since-last-update
        emit DepositRewards(msg.value);
    }

    receive() external payable {
        depositRewards();
    }

	/// @param _wrap wrap native token before sending?
    /// @param _to address to send reward token to
    /// @param _amount value of reward token to transfer
    function safeTransferReward(bool _wrap, address _to, uint256 _amount) internal {
        rewardsPending -= toUint128(_amount);
		if (_wrap) {
			WNATIVE.deposit{value: _amount}();
			WNATIVE.safeTransfer(_to, _amount);
		} else {
			MoneyBomb.safePay(payable(_to), _amount);
		}
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
    function setRewardHalflife(uint40 _rewardHalflife) external onlyOwner {
        updatePool();
        rewardHalflife = _rewardHalflife;
        emit LogUpdatePool(_rewardHalflife);
    }

        /// @dev Remove excess stake tokens earned by reflect fees
    function skimStakeTokenFees() external onlyOwner {
        uint256 stakeTokenFeeBalance = getStakeTokenFeeBalance();
        lpToken.safeTransfer(msg.sender, stakeTokenFeeBalance);
        emit SkimStakeTokenFees(msg.sender, stakeTokenFeeBalance);
    }

    /* Emergency Functions */

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() external {
        UserInfo storage user = userInfo[msg.sender];
        lpToken.safeTransfer(msg.sender, user.amount);
        totalStaked = totalStaked - user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        updatePool();
        require(_amount <= address(this).balance - rewardsPending, 'not enough rewards');
        // Withdraw rewards
        (bool success,) = msg.sender.call{value: _amount}("");
        require(success, "Reward transfer failed");
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    /// @notice A public function to sweep accidental BEP20 transfers to this contract.
    ///   Tokens are sent to owner
    /// @param token The address of the BEP20 token to sweep
    function sweepToken(IERC20 token) external onlyOwner {
        require(token != lpToken, "cannot sweep staked token");
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
        emit EmergencySweepWithdraw(msg.sender, token, balance);
    }

    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    function toUint176(uint256 value) internal pure returns (uint176) {
        require(value <= type(uint176).max, "SafeCast: value doesn't fit in 176 bits");
        return uint176(value);
    }

}