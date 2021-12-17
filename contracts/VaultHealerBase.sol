// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "./libs/IBoostPool.sol";
import "./libs/IStrategy.sol";

abstract contract VaultHealerBase is Ownable, ERC1155Supply { //ReentrancyGuard, 
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;

    struct PoolInfo {
        IERC20 want; //  want token.
        bool paused; //vault is paused?
        IStrategy strat; // Strategy contract that will auto compound want tokens
        bool overrideDefaultFees; // strategy's fee config doesn't change with the vaulthealer's default
        VaultFees fees;
        uint256 maximizerVaultPid; // vh pid of maximizer, 0 if not a maximizer
        uint256 accRewardTokensPerShare;
        uint256 balanceCrystlCompounderLastUpdate;
        mapping (address => uint256) rewardDebt; // rewardDebt per user per maximizer
        IBoostPool boostPool;
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
    }
    
    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }
    function poolInfo(uint pid) external view returns (address want, address strat) {
        return (address(_poolInfo[pid].want), address(_poolInfo[pid].strat));
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        uint256 _sharesTotal = totalSupply(_pid); //balanceOf(_user, _pid);
        if (_sharesTotal == 0) return 0;

        PoolInfo storage pool = _poolInfo[_pid];
        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        
        return balanceOf(_user, _pid) * wantLockedTotal / _sharesTotal;
    }

    // View function to see staked Want tokens on frontend.
    function boostedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = _poolInfo[_pid];
        
        uint256 _sharesTotal = totalSupply(_pid);
        if (_sharesTotal == 0) return 0;
        
        IBoostPool boostPool = pool.boostPool;
        if (address(boostPool) == address(0)) return 0;

        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        
        return boostPool.userStakedAmount(_user) * wantLockedTotal / _sharesTotal;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner  { //nonReentrant
        require(!isStrat(_strat), "Existing strategy");
        _poolInfo.push();
        PoolInfo storage pool = _poolInfo[_poolInfo.length - 1];
        IStrategy strat = IStrategy(_strat);

        pool.want = strat.wantToken();
        pool.strat = strat;
        strat.setFees(defaultFees);
        // pool.boostPoolAddress = strat.boostPoolAddress();
        
        address maximizerVault = address(strat.maximizerVault());
        require(strat.isMaximizer() != (maximizerVault == address(0)), "bad maximizer");
        pool.maximizerVaultPid = _strats[maximizerVault];
        require(
            (maximizerVault == address(0)) == (pool.maximizerVaultPid == 0),
            "maximizer not set up"
        );

        _strats[_strat] = _poolInfo.length - 1;
        emit AddPool(_strat);
    }
    
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
            PoolInfo storage pool = _poolInfo[i];
            if (pool.overrideDefaultFees) continue;
            try pool.strat.setFees(_fees) {}
            catch { emit SetDefaultFail(i); }
        }
    }   
    function setFees(uint _pid, VaultFees calldata _fees) external onlyOwner {
        PoolInfo storage pool = _poolInfo[_pid];
        pool.overrideDefaultFees = true;
        pool.fees = _fees;
        emit SetFees(_pid, _fees);
    }
    function resetFees(uint _pid) external onlyOwner {
        PoolInfo storage pool = _poolInfo[_pid];
        pool.overrideDefaultFees = false;
        delete pool.fees;
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
    function earn(uint256 pid) external whenNotPaused(pid)  { //nonReentrant
        _poolInfo[pid].strat.earn(_msgSender());
    }
    
    function setBoostPoolAddress(uint pid, address _boostPoolAddress) external onlyOwner {
        _poolInfo[pid].boostPool = IBoostPool(_boostPoolAddress);
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
