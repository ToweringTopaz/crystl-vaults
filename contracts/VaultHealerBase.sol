// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "./libs/IBoostPool.sol";
import "./libs/IStrategy.sol";

abstract contract VaultHealerBase is Ownable, ERC1155Supply, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;
    using BitMaps for BitMaps.BitMap;

    struct PoolInfo {
        IERC20 want; //  want token.
        IStrategy strat; // Strategy contract that will auto compound want tokens
        bool overrideDefaultEarnFees; // strategy's fee config doesn't change with the vaulthealer's default
        bool overrideDefaultWithdrawFee;
        VaultFee withdrawFee;
        uint256 accRewardTokensPerShare;
        uint256 balanceCrystlCompounderLastUpdate;
        uint256 maximizerPid;
        // bytes data;
    }

    PoolInfo[] internal _poolInfo; // Info of each pool.
    BitMaps.BitMap private pauseMap; //Boolean pause status for each vault; true == unpaused
    mapping(uint256 => mapping(address => uint256)) public rewardDebt; // rewardDebt per user per maximizer
    VaultFees public defaultEarnFees; // Settings which are generally applied to all strategies
    VaultFee public defaultWithdrawFee; //withdrawal fee is set separately from earn fees

    //pid for any of our strategies
    mapping(address => uint) private _strats;
    
    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetDefaultEarnFees(VaultFees _earnFees);
    event SetDefaultFail(uint pid);
    event SetEarnFees(uint pid, VaultFees _earnFees);
    event SetWithdrawFee(uint pid, VaultFee _withdrawFee);
    event ResetEarnFees(uint pid);
    event Paused(uint pid);
    event Unpaused(uint pid);
    
    constructor(VaultFees memory _earnFees, VaultFee memory _withdrawFee) ERC1155("") {
        _earnFees.check();
        defaultEarnFees = _earnFees;
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultEarnFees(_earnFees);

        _poolInfo.push(); //so uninitialized pid variables (pid 0) can be assumed as invalid
    }
    
    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }
    function poolInfo(uint pid) external view returns (IERC20 want, IStrategy strat) {
        return (_poolInfo[pid].want, _poolInfo[pid].strat);
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
        if (pool.strat.boostPoolAddress() == address(0)) return 0;
        
        IBoostPool boostPool = IBoostPool(pool.strat.boostPoolAddress());
        uint256 _sharesTotal = totalSupply(_pid);
        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        if (_sharesTotal == 0) {
            return 0;
        }
        return boostPool.userStakedAmount(_user) * wantLockedTotal / _sharesTotal;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner nonReentrant {
        require(!isStrat(_strat), "Existing strategy");
        IStrategy strat = IStrategy(_strat);
        uint pid = _poolInfo.length;
        _poolInfo.push();
        PoolInfo storage pool = _poolInfo[pid];
        pool.want = strat.wantToken();
        pool.strat = strat;
        pool.maximizerPid = _strats[address(strat.maximizerVault())];
        console.log("pid:", pid);
        console.log("want:", address(pool.want));
        console.log("maximizer address:", address(strat.maximizerVault()));
        console.log("maximizer pid:", pool.maximizerPid);
        console.log("is maximizer:", strat.isMaximizer());
        strat.setEarnFees(defaultEarnFees);
        pool.withdrawFee = defaultWithdrawFee; //I've added this line in to set fees in the VH based pool as well as in the strat's vaultFees struct
        // pool.boostPoolAddress = strat.boostPoolAddress();
        
        _strats[_strat] = pid;
        _unpause(pid);
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
    
    function getEarnFees(uint _pid) public view returns (VaultFees memory) {
        PoolInfo storage pool = _poolInfo[_pid];
        if (pool.overrideDefaultEarnFees) 
            return pool.strat.earnFees();
        else
            return defaultEarnFees;
    }
    
     function setDefaultEarnFees(VaultFees calldata _earnFees) external onlyOwner {
        defaultEarnFees = _earnFees;
        emit SetDefaultEarnFees(_earnFees);
        
        for (uint i; i < _poolInfo.length; i++) {
            if (_poolInfo[i].overrideDefaultEarnFees) continue;
            try _poolInfo[i].strat.setEarnFees(_earnFees) {}
            catch { emit SetDefaultFail(i); }
        }
    }   
    function setEarnFees(uint _pid, VaultFees calldata _earnFees) external onlyOwner {
        _poolInfo[_pid].overrideDefaultEarnFees = true;
        _poolInfo[_pid].strat.setEarnFees(_earnFees);
        emit SetEarnFees(_pid, _earnFees);
    }
    function resetEarnFees(uint _pid) external onlyOwner {
        _poolInfo[_pid].overrideDefaultEarnFees = false;
        _poolInfo[_pid].strat.setEarnFees(defaultEarnFees);
        emit ResetEarnFees(_pid);
    }
    
    function getWithdrawFee(uint _pid) public view returns (VaultFee memory) {
        return _poolInfo[_pid].withdrawFee;
    }

    function setWithdrawFee(uint _pid, VaultFee calldata _withdrawFee) external onlyOwner {
        _poolInfo[_pid].overrideDefaultWithdrawFee = true;
        _poolInfo[_pid].withdrawFee = _withdrawFee;
        emit SetWithdrawFee(_pid, _withdrawFee);
    }
    
    function earnAll() external nonReentrant {

        uint bucketLength = (_poolInfo.length >> 8) + 1; // use one uint256 per 256 vaults

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i]; //earn unpaused vaults

            uint end = (i+1) << 8; // buckets end at multiples of 256
            if (_poolInfo.length < end) end = _poolInfo.length; //or if less, the final pool
            for (uint j = i << 8; j < end; j++) {
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    try _poolInfo[j].strat.earn(_msgSender()) {}
                    catch {}
                }
                earnMap >>= 1; //shift away the used bit
                if (earnMap == 0) break;
            }
        }
    }
    
    function earnSome(uint256[] memory pids) external nonReentrant {

        uint bucketLength = (_poolInfo.length >> 8) + 1; // use one uint256 per 256 vaults
        uint256[] memory selBuckets = new uint256[](bucketLength); //BitMap of selected pids

        for (uint i; i < pids.length; i++) { //memory bitmap of all selected pids
            uint pid = pids[i];
            if (pid <= _poolInfo.length)
                selBuckets[pid >> 8] |= 1 << (pid & 0xff); //set bit for selected pid
        }

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i] & selBuckets[i]; //earn selected, unpaused vaults

            uint end = (i+1) << 8; // buckets end at multiples of 256
            for (uint j = i << 8; j < end; j++) {//0-255, 256-511, ...
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    try _poolInfo[j].strat.earn(_msgSender()) {}
                    catch {}
                }
                earnMap >>= 1; //shift away the used bit
                if (earnMap == 0) break; //if bucket is empty, done with bucket
            }
        }
    }
    function earn(uint256 pid) external whenNotPaused(pid) nonReentrant {
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
        return !pauseMap.get(pid);
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
        pauseMap.unset(pid);
        emit Paused(pid);
    }
    function _unpause(uint pid) internal virtual whenPaused(pid) {
        require(pid > 0 && pid < _poolInfo.length, "invalid pid");
        pauseMap.set(pid);
        emit Unpaused(pid);
    }
}
