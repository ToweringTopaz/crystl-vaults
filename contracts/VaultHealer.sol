// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./libs/IStrategy.sol";
import "./libs/IUniPair.sol";

contract VaultHealer is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
    }

    struct PoolInfo {
        IERC20 want; // Address of the want token.
        IStrategy strat; // Strategy address that will auto compound want tokens
    }

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    mapping(address => bool) private strats;

    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner nonReentrant {
        require(!strats[_strat], "Existing strategy");
        poolInfo.push(
            PoolInfo({
                want: IERC20(IStrategy(_strat).wantAddress()),
                strat: IStrategy(_strat)
            })
        );
        strats[_strat] = true;
        resetSingleAllowance(poolInfo.length - 1);
        emit AddPool(_strat);
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = pool.strat.sharesTotal();
        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return user.shares * wantLockedTotal / sharesTotal;
    }

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt) external nonReentrant {
        _deposit(_pid, _wantAmt, msg.sender);
    }

    // For depositing for other users
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant {
        _deposit(_pid, _wantAmt, _to);
    }

    function _deposit(uint256 _pid, uint256 _wantAmt, address _to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        require(address(pool.strat) != address(0), "That strategy does not exist");
        UserInfo storage user = userInfo[_pid][_to];

        if (_wantAmt > 0) {
            // Call must happen before transfer
            uint256 wantBefore = pool.want.balanceOf(address(this));
            pool.want.safeTransferFrom(msg.sender, address(this), _wantAmt);
            uint256 finalDeposit = pool.want.balanceOf(address(this)) - wantBefore;

            // Proper deposit amount for tokens with fees
            uint256 sharesAdded = poolInfo[_pid].strat.deposit(_to, finalDeposit);
            user.shares += sharesAdded;
        }
        emit Deposit(_to, _pid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) external nonReentrant {
        _withdraw(_pid, _wantAmt, msg.sender);
    }

    // For withdrawing to other address
    function withdraw(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant {
        _withdraw(_pid, _wantAmt, _to);
    }

    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        require(address(pool.strat) != address(0), "That strategy does not exist");
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        uint256 sharesTotal = pool.strat.sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw want tokens
        uint256 amount = user.shares * wantLockedTotal / sharesTotal;
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved = pool.strat.withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares -= sharesRemoved;
            }

            uint256 wantBal = pool.want.balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(_to, _wantAmt);
        }
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    // Withdraw everything from pool for yourself
    function withdrawAll(uint256 _pid) external {
        _withdraw(_pid, type(uint256).max, msg.sender);
    }

    function resetAllowances() external onlyOwner {
        for (uint256 i; i < poolInfo.length; i++) {
            PoolInfo storage pool = poolInfo[i];
            pool.want.safeApprove(address(pool.strat), 0);
            pool.want.safeIncreaseAllowance(address(pool.strat), type(uint256).max);
        }
    }

    function earnAll() external {
        for (uint256 i; i < poolInfo.length; i++) {
            try poolInfo[i].strat.earn(_msgSender()) {}
            catch {}
        }
    }

    function earnSome(uint256[] memory pids) external {
        for (uint256 i; i < pids.length; i++) {
            if (poolInfo.length >= pids[i]) {
                try poolInfo[pids[i]].strat.earn(_msgSender()) {}
                catch {}
            }
        }
    }

    function resetSingleAllowance(uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        pool.want.safeApprove(address(pool.strat), 0);
        pool.want.safeIncreaseAllowance(address(pool.strat), type(uint256).max);
    }
    function strategyWantMigration(IUniPair _newWant) external {
        require (strats[msg.sender], "only callable by strategies");
        for (uint i; i < poolInfo.length; i++) {
            if (address(poolInfo[i].strat) == msg.sender) {
                address token0 = IUniPair(address(poolInfo[i].want)).token0();
                address token1 = IUniPair(address(poolInfo[i].want)).token1();
                require(token0 == IUniPair(_newWant).token0() && token1 == IUniPair(_newWant).token1(), "old/new tokens don't match");
                poolInfo[i].want = _newWant;
                return;
            }
        }
        revert("VH failed to migrate want");
    }
}