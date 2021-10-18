// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libs/LibVaultConfig.sol";

interface IStrategy {
    function wantToken() external view returns (IERC20); // Want address
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    function earn(address _to) external; // Main want token compounding function
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved, uint256 wantAmt);
    function setFees(VaultFees calldata _fees) external; //vaulthealer uses this to update configuration
    function panic() external;
    function unpanic() external;
}

abstract contract VaultHealerBase is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;

    // Info of each user.
    struct UserInfo {
        uint256 shares; // Shares for standard auto-compound rewards
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        mapping (address => uint256) allowances; //for ERC20 transfers
        bytes data;
    }
    struct PoolInfo {
        IERC20 want; // Address of the want token.
        bool paused; //vault is paused?
        IStrategy strat; // Strategy address that will auto compound want tokens
        bool overrideDefaultFees; // strategy's fee config doesn't change with the vaulthealer's default
        VaultFees fees;
        mapping (address => UserInfo) user;
        uint256 sharesTotal;
        bytes data;
    }
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint256 amount;
    }

    PoolInfo[] internal _poolInfo; // Info of each pool.
    VaultFees public defaultFees; // Settings which are generally applied to all strategies
    uint8 public withdrawFeeRate; // in basis points: 255 = 2.55% max possible withdrawal fee
    
    //pid+1 for any of our strategies. +1 allows us to distinguish pid 0 from an unauthorized address
    mapping(address => uint) private _strats;
    
    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetDefaultFees(VaultFees _fees);
    event SetDefaultFail(uint pid);
    event SetFees(uint pid, VaultFees _fees);
    event ResetFees(uint pid);
    event Paused(uint pid);
    event Unpaused(uint pid);
    
    constructor(VaultFees memory _fees) {
        _fees.check();
        defaultFees = _fees;
        emit SetDefaultFees(_fees);
    }

    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }
    function poolInfo(uint pid) external view returns (address want, address strat) {
        return (address(_poolInfo[pid].want), address(_poolInfo[pid].strat));
    }
    
    function userInfo(uint _pid, address _user) external view returns (uint256 shares) {
        return _poolInfo[_pid].user[_user].shares;
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
    function userTotals(uint256 _pid, address _user) external view returns (uint256 deposited, uint256 withdrawn, int256 earned) {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = pool.user[_user];
        
        deposited = user.totalDeposits;
        withdrawn = user.totalWithdrawals;
        uint staked = pool.sharesTotal == 0 ? 0 : user.shares * pool.strat.wantLockedTotal() / pool.sharesTotal;
        earned = int(withdrawn + staked) - int(deposited);
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner nonReentrant {
        require(!isStrat(_strat), "Existing strategy");
        _poolInfo.push();
        PoolInfo storage pool = _poolInfo[_poolInfo.length - 1];
        pool.want = IStrategy(_strat).wantToken();
        pool.strat = IStrategy(_strat);
        IStrategy(_strat).setFees(defaultFees);
        
        _strats[_strat] = _poolInfo.length;
        emit AddPool(_strat);
    }
    
    //enables sharesTotal function on strategy
    function sharesTotal(address _strat) external view returns (uint) {
        uint pid = findPid(_strat);
        return _poolInfo[pid].sharesTotal;
    }
    function isStrat(address _strat) public view returns (bool) {
        return _strats[_strat] > 0;
    }
    function findPid(address _strat) public view returns (uint) {
        uint pidPlusOne = _strats[_strat];
        require(pidPlusOne > 0, "address is not a strategy on this VaultHealer"); //must revert here for security
        return pidPlusOne - 1;
    }
    
    function getFees(uint pid) public view returns (VaultFees memory) {
        PoolInfo storage pool = _poolInfo[pid];
        if (pool.overrideDefaultFees) 
            return pool.fees;
        else
            return defaultFees;
    }
    
     function setDefaultFees(VaultFees calldata _fees) external onlyOwner {
        defaultFees = _fees;
        emit SetDefaultFees(_fees);
        
        for (uint i; i < _poolInfo.length; i++) {
            if (_poolInfo[i].overrideDefaultFees) continue;
            try _poolInfo[i].strat.setFees(_fees) {}
            catch { emit SetDefaultFail(i); }
        }
    }   
    function setFees(uint _pid, VaultFees calldata _fees) external onlyOwner {
        _poolInfo[_pid].overrideDefaultFees = true;
        _poolInfo[_pid].fees = _fees;
        emit SetFees(_pid, _fees);
    }
    function resetFees(uint _pid) external onlyOwner {
        _poolInfo[_pid].overrideDefaultFees = false;
        delete _poolInfo[_pid].fees;
        emit ResetFees(_pid);
    }
    
    function earnAll() external nonReentrant {
        for (uint256 i; i < _poolInfo.length; i++) {
            if (!paused(i)) {
                try _poolInfo[i].strat.earn(_msgSender()) {}
                catch {}
            }
        }
    }

    function earnSome(uint256[] memory pids) external nonReentrant {
        for (uint256 i; i < pids.length; i++) {
            if (_poolInfo.length >= pids[i] && !paused(pids[i])) {
                try _poolInfo[pids[i]].strat.earn(_msgSender()) {}
                catch {}
            }
        }
    }
    function earn(uint256 pid) external nonReentrant whenNotPaused(pid) {
        _poolInfo[pid].strat.earn(_msgSender());
    }
    
    
    //Like OpenZeppelin Pausable, but centralized here at the vaulthealer
    ///////////////////////
    function pause(uint pid) external onlyOwner {
        _pause(pid);
    }
    function unpause(uint pid) external onlyOwner {
        _unpause(pid);
    }
    function panic(uint pid) external onlyOwner {
        _pause(pid);
        _poolInfo[pid].strat.panic();
    }
    function unpanic(uint pid) external onlyOwner {
        _unpause(pid);
        _poolInfo[pid].strat.unpanic();
    }
    
    function paused(address _strat) external view returns (bool) {
        return paused(findPid(_strat));
    }
    function paused(uint pid) public view returns (bool) {
        return _poolInfo[pid].paused;
    }
    modifier whenNotPaused(uint pid) {
        require(!paused(pid), "Pausable: paused");
        _;
    }
    modifier whenPaused(uint pid) {
        require(paused(pid), "Pausable: not paused");
        _;
    }
    function _pause(uint pid) internal virtual whenNotPaused(pid) {
        _poolInfo[pid].paused = true;
        emit Paused(pid);
    }
    function _unpause(uint pid) internal virtual whenPaused(pid) {
        _poolInfo[pid].paused = false;
        emit Unpaused(pid);
    }
}
