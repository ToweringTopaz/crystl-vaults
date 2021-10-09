// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libs/LibVaultHealer.sol";

interface IStrategy {
    function wantAddress() external view returns (address); // Want address
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    function paused() external view returns (bool); // Is strategy paused
    function earn(address _to) external; // Main want token compounding function
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved, uint256 wantAmt);
    function pushConfig(LibVaultHealer.Config calldata _config) external; //vaulthealer uses this to update configuration
}

abstract contract VaultHealerBase is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 shares; // Shares for standard auto-compound rewards
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        mapping (address => uint256) allowances; //for ERC20 transfers
    }
    struct PoolInfo {
        IERC20 want; // Address of the want token.
        IStrategy strat; // Strategy address that will auto compound want tokens
        uint256 sharesTotal;
        mapping (address => UserInfo) user;
        bool overrideDefaults; // use config here instead of defaults?
        LibVaultHealer.Config config;
        bool paused;
    }
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint256 amount;
    }


    PoolInfo[] internal _poolInfo; // Info of each pool.
    LibVaultHealer.Config public defaultConfig; // Settings which are generally applied to all strategies
    
    
    //pid+1 for any of our strategies. +1 allows us to distinguish pid 0 from an unauthorized address
    mapping(address => uint) private _strats;
    
    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetDefaultConfig(LibVaultHealer.Config _config);
    event SetConfig(uint pid, LibVaultHealer.Config _config);
    event ResetConfig(uint pid);
    
    constructor(LibVaultHealer.Config memory _config) {
        LibVaultHealer.checkConfig(_config);
        defaultConfig = _config;
        emit SetDefaultConfig(_config);
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
        pool.want = IERC20(IStrategy(_strat).wantAddress());
        pool.strat = IStrategy(_strat);
        
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
    
     function setDefaultConfig(LibVaultHealer.Config calldata _config) external onlyOwner {
        defaultConfig = _config;
        emit SetDefaultConfig(_config);
        
        for (uint i; i < _poolInfo.length; i++) {
            if (_poolInfo[i].overrideDefaults) continue;
            _poolInfo[i].strat.pushConfig(_config);
        }
    }   
    function setConfig(uint _pid, LibVaultHealer.Config calldata _config) external onlyOwner {
        _poolInfo[_pid].overrideDefaults = true;
        _poolInfo[_pid].config = _config;
        emit SetConfig(_pid, _config);
    }
    function resetConfig(uint _pid) external onlyOwner {
        _poolInfo[_pid].overrideDefaults = false;
        delete _poolInfo[_pid].config;
        emit ResetConfig(_pid);
    }
    
    function getConfig(uint _pid) external view returns (LibVaultHealer.Config memory config) {
        return _poolInfo[_pid].overrideDefaults ? _poolInfo[_pid].config : defaultConfig;
    }
    function getConfig() external view returns (LibVaultHealer.Config memory config) {
        uint _pidPlus1 =_strats[msg.sender];
        return _pidPlus1 > 0 && _poolInfo[_pidPlus1].overrideDefaults ? _poolInfo[_pidPlus1].config : defaultConfig;
    }
    function paused(address strat) public view returns (bool) {
        
    }

}
