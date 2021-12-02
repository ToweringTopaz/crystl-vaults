// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "./libs/IStakingPool.sol";
// import "./libs/LibVaultConfig.sol";
import "./libs/IStrategy.sol";

abstract contract VaultHealerBase is Ownable, ERC1155Supply {
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;

    // Info of each user.
    struct UserInfo {
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        mapping (address => uint256) allowances; //for ERC20 transfers
        bytes data;
    }
    struct PoolInfo {
        IERC20 want; //  want token.
        bool paused; //vault is paused?
        IStrategy strat; // Strategy contract that will auto compound want tokens
        bool overrideDefaultFees; // strategy's fee config doesn't change with the vaulthealer's default
        VaultFees fees;
        mapping (address => UserInfo) user;
        bytes data;
    }

    PoolInfo[] internal _poolInfo; // Info of each pool.
    VaultFees public defaultFees; // Settings which are generally applied to all strategies
    
    //pid for any of our strategies
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
    
    constructor(VaultFees memory _fees) ERC1155("") {
        _fees.check();
        defaultFees = _fees;
        emit SetDefaultFees(_fees);

        _poolInfo.push(); //so uninitialized pid variables (pid 0) can be assumed as invalid
        
        //_reentrancyStatus = _NOT_ENTERED;
    }
    
    // uint private _reentrancyStatus;
    // uint private constant _NOT_ENTERED = type(uint).max;
    // uint private constant _ENTERED = type(uint).max - 1;
    
    // //identical in effect to OpenZeppelin nonReentrant
    // modifier nonReentrant() {
    //     require (_reentrancyStatus == _NOT_ENTERED, "VaultHealer: reentrant call");
    //     _reentrancyStatus = _ENTERED;
    //     _;
    //     _reentrancyStatus = _NOT_ENTERED;
    // }
    // //identical in effect to OpenZeppelin nonReentrant but stores the pid
    // modifier nonReentrantPid(uint pid) {
    //     require (_reentrancyStatus == _NOT_ENTERED, "VaultHealer: reentrant call");
    //     require (pid < _poolInfo.length, "VaultHealer: bad pid");
    //     _reentrancyStatus = pid;
    //     _;
    //     _reentrancyStatus = _NOT_ENTERED;
    // }
    // //function call must be a reentrant call by the strategy associated with the PID stored at _reentrancyStatus
    // modifier onlyReentrantPid() {
    //     require(_reentrancyStatus == _strats[msg.sender]);
    //     _;
    // }

    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }
    function poolInfo(uint pid) external view returns (address want, address strat) {
        return (address(_poolInfo[pid].want), address(_poolInfo[pid].strat));
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = _poolInfo[_pid];

        uint256 _sharesTotal = totalSupply(_pid); //balanceOf(_user, _pid);
        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        if (_sharesTotal == 0) {
            return 0;
        }
        return balanceOf(_user, _pid) * wantLockedTotal / _sharesTotal;
    }

    // View function to see staked Want tokens on frontend.
    function boostedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = _poolInfo[_pid];
        if (pool.strat.stakingPoolAddress() == address(0)) return 0;
        
        IStakingPool stakingPool = IStakingPool(pool.strat.stakingPoolAddress());
        uint256 _sharesTotal = totalSupply(_pid);
        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        if (_sharesTotal == 0) {
            return 0;
        }
        return stakingPool.userStakedAmount(_user) * wantLockedTotal / _sharesTotal;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner  { //nonReentrant
        require(!isStrat(_strat), "Existing strategy");
        _poolInfo.push();
        PoolInfo storage pool = _poolInfo[_poolInfo.length - 1];
        pool.want = IStrategy(_strat).wantToken();
        pool.strat = IStrategy(_strat);
        IStrategy(_strat).setFees(defaultFees);
        // pool.stakingPoolAddress = IStrategy(_strat).stakingPoolAddress();
        
        _strats[_strat] = _poolInfo.length - 1;
        emit AddPool(_strat);
    }
    
    //     function addStakingPool(uint256 _pid, address _stakingPool) external onlyOwner nonReentrant {
    //     require(!isStrat(_strat), "Existing strategy");
    //     _poolInfo[_pid] = IStrategy(_strat).stakingPoolAddress();
    // }
    
    //enables sharesTotal function on strategy
    function sharesTotal(address _strat) external view returns (uint) {
        uint pid = findPid(_strat);
        return totalSupply(pid);
    }
    function isStrat(address _strat) public view returns (bool) {
        return _strats[_strat] > 0;
    }
    function findPid(address _strat) public view returns (uint) {
        uint pid = _strats[_strat];
        require(pid > 0, "address is not a strategy on this VaultHealer"); //must revert here for security
        return pid;
    }
    
    // function getFees(uint pid) public view returns (VaultFees memory) {
    //     PoolInfo storage pool = _poolInfo[pid];
    //     if (pool.overrideDefaultFees) 
    //         return pool.fees;
    //     else
    //         return defaultFees;
    // }
    
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
    
    function earnAll() external  { //nonReentrant
        for (uint256 i; i < _poolInfo.length; i++) {
            if (!paused(i)) {
                try _poolInfo[i].strat.earn(_msgSender()) {}
                catch {}
            }
        }
    }

    function earnSome(uint256[] memory pids) external  { //nonReentrant
        for (uint256 i; i < pids.length; i++) {
            if (_poolInfo.length >= pids[i] && !paused(pids[i])) {
                try _poolInfo[pids[i]].strat.earn(_msgSender()) {}
                catch {}
            }
        }
    }
    function earn(uint256 pid) external  whenNotPaused(pid) { //nonReentrant
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
