// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Magnetite.sol";

import "./libs/Boolean256.sol";

interface IStrategy {
    function wantAddress() external view returns (address); // Want address
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    function paused() external view returns (bool); // Is strategy paused
    function earn(address _to) external; // Main want token compounding function
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved);
}

contract VaultHealer is ReentrancyGuard, Magnetite {

    using SafeERC20 for IERC20;

    uint constant MAX_STRATS = 256; // code only supports 256 strats

    // Info of each user.
    struct UserInfo {
        uint shares; // Shares for standard auto-compound rewards
        uint xTokensTotal; //Total tokens the user has earning/exporting at this pool
        bool256 allImports; // all contracts from which this user/pool import shares
        bool256 allExports; // all contracts to whom this user/pool export shares
        mapping(uint => uint) xTokens; // amount of tokens exporting to the uint16 pid
    }

    struct PoolInfo {
        IERC20 want; // Address of the want token.
        IStrategy strat; // Strategy address that will auto compound want tokens
        uint256 sharesTotal;
        mapping (address => UserInfo) user;
    }
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint256 amount;
    }

    PoolInfo[] internal _poolInfo; // Info of each pool.
    
    //pid+1 for any of our strategies. +1 allows us to distinguish pid 0 from an unauthorized address
    mapping(address => uint) private _strats;
    
    PendingDeposit private pendingDeposit;

    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }
    function poolInfo(uint pid) external view returns (address want, address strat) {
        return (address(_poolInfo[pid].want), address(_poolInfo[pid].strat));
    }
    
    function userInfo(uint _pid, address _user) external view returns (uint256 shares) {
        return _poolInfo[_pid].user[_user].shares;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner nonReentrant {
        require(!isStrat(_strat), "Existing strategy");
        _poolInfo.push();
        PoolInfo storage pool = _poolInfo[_poolInfo.length - 1];
        pool.want = IERC20(IStrategy(_strat).wantAddress());
        pool.strat = IStrategy(_strat);
        
        _strats[_strat] = _poolInfo.length;
        emit AddPool(_strat);
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = pool.user[_user];

        uint256 _sharesTotal = pool.sharesTotal;
        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        if (_sharesTotal == 0) {
            return 0;
        }
        return user.shares * wantLockedTotal / _sharesTotal;
    }
    //enables sharesTotal function on strategy
    function sharesTotal(address _strat) external view returns (uint) {
        return _poolInfo[findPid(_strat)].sharesTotal;
    }
    function isStrat(address _strat) public view returns (bool) {
        return _strats[_strat] > 0;
    }
    function findPid(address _strat) public view returns (uint) {
        uint pidPlusOne = _strats[_strat];
        require(pidPlusOne > 0, "address is not a strategy on this VaultHealer");
        return pidPlusOne - 1;
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
        PoolInfo storage pool = _poolInfo[_pid];
        require(address(pool.strat) != address(0), "That strategy does not exist");

        if (_wantAmt > 0) {
            
            UserInfo storage user = pool.user[_to];
            
            pendingDeposit = PendingDeposit({
                token: pool.want,
                from: msg.sender,
                amount: _wantAmt
            });

            uint256 sharesAdded = pool.strat.deposit(msg.sender, _to, _wantAmt, pool.sharesTotal);
            user.shares += sharesAdded;
            pool.sharesTotal += sharesAdded;
            
            delete pendingDeposit;
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
        PoolInfo storage pool = _poolInfo[_pid];
        require(address(pool.strat) != address(0), "That strategy does not exist");
        UserInfo storage user = pool.user[msg.sender];

        require(user.shares > 0, "user.shares is 0");

        uint256 sharesRemoved = pool.strat.withdraw(msg.sender, _to, _wantAmt, user.shares, pool.sharesTotal);

        user.shares -= sharesRemoved;
        pool.sharesTotal -= sharesRemoved;

        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    // Withdraw everything from pool for yourself
    function withdrawAll(uint256 _pid) external {
        _withdraw(_pid, type(uint256).max, msg.sender);
    }

    function earnAll() external nonReentrant {
        for (uint256 i; i < _poolInfo.length; i++) {
            try _poolInfo[i].strat.earn(_msgSender()) {}
            catch {}
        }
    }

    function earnSome(uint256[] memory pids) external nonReentrant {
        for (uint256 i; i < pids.length; i++) {
            if (_poolInfo.length >= pids[i]) {
                try _poolInfo[pids[i]].strat.earn(_msgSender()) {}
                catch {}
            }
        }
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint _amount) external {
        require(isStrat(msg.sender));
        pendingDeposit.amount -= _amount;
        pendingDeposit.token.safeTransferFrom(
            pendingDeposit.from,
            _to,
            _amount
        );
    }
    
    //allows strats to generate paths
    function pathAuth() internal override view returns (bool) {
        return super.pathAuth() || isStrat(msg.sender);
    }
}