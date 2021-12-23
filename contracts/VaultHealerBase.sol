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

    struct VaultInfo {
        IERC20 want; //  want token.
        IStrategy strat; // Strategy contract that will auto compound want tokens
        VaultFee withdrawFee;
        uint256 accRewardTokensPerShare;
        uint256 balanceCrystlCompounderLastUpdate;
        uint256 targetVid; //maximizer target, which accumulates tokens
        mapping(address => uint256) rewardDebt;
        // bytes data;
    }

    VaultInfo[] internal _vaultInfo; // Info of each vault.
    BitMaps.BitMap private pauseMap; //Boolean pause status for each vault; true == unpaused
    BitMaps.BitMap private _overrideDefaultEarnFees; // strategy's fee config doesn't change with the vaulthealer's default
    BitMaps.BitMap private _overrideDefaultWithdrawFee;
    VaultFees public defaultEarnFees; // Settings which are generally applied to all strategies
    VaultFee public defaultWithdrawFee; //withdrawal fee is set separately from earn fees

    //vid for any of our strategies
    mapping(address => uint) private _strats;
    
    event AddVault(address indexed strat);
    event Deposit(address indexed user, uint256 indexed vid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed vid, uint256 amount);
    event SetDefaultEarnFees(VaultFees _earnFees);
    event SetDefaultFail(uint vid);
    event SetEarnFees(uint vid, VaultFees _earnFees);
    event SetWithdrawFee(uint vid, VaultFee _withdrawFee);
    event ResetEarnFees(uint vid);
    event Paused(uint vid);
    event Unpaused(uint vid);
    
    constructor(VaultFees memory _earnFees, VaultFee memory _withdrawFee) ERC1155("") {
        _earnFees.check();
        defaultEarnFees = _earnFees;
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultEarnFees(_earnFees);

        _vaultInfo.push(); //so uninitialized vid variables (vid 0) can be assumed as invalid
    }
    
    function vaultLength() external view returns (uint256) {
        return _vaultInfo.length;
    }
    function vaultInfo(uint vid) external view returns (IERC20 want, IStrategy strat) {
        return (_vaultInfo[vid].want, _vaultInfo[vid].strat);
    }

    function rewardDebt(uint vid, address user) external view returns (uint) {
        return _vaultInfo[vid].rewardDebt[user];
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _vid, address _user) external view returns (uint256) {
        VaultInfo storage vault = _vaultInfo[_vid];

        uint256 _sharesTotal = totalSupply(_vid); //balanceOf(_user, _vid);
        uint256 wantLockedTotal = vault.strat.wantLockedTotal();
        if (_sharesTotal == 0) {
            return 0;
        }
        return balanceOf(_user, _vid) * wantLockedTotal / _sharesTotal;
    }

    // View function to see staked Want tokens on frontend.
    function boostedWantTokens(uint256 _vid, address _user) external view returns (uint256) {
        VaultInfo storage vault = _vaultInfo[_vid];
        if (vault.strat.boostPoolAddress() == address(0)) return 0;
        
        IBoostPool boostPool = IBoostPool(vault.strat.boostPoolAddress());
        uint256 _sharesTotal = totalSupply(_vid);
        uint256 wantLockedTotal = vault.strat.wantLockedTotal();
        if (_sharesTotal == 0) {
            return 0;
        }
        return boostPool.userStakedAmount(_user) * wantLockedTotal / _sharesTotal;
    }

    /**
     * @dev Add a new want to the vault. Can only be called by the owner.
     */
    function addVault(address _strat) external onlyOwner nonReentrant {
        require(!isStrat(_strat), "Existing strategy");
        IStrategy strat = IStrategy(_strat);
        uint vid = _vaultInfo.length;
        _vaultInfo.push();
        VaultInfo storage vault = _vaultInfo[vid];
        vault.want = strat.wantToken();
        vault.strat = strat;
        vault.targetVid = _strats[address(strat.targetVault())];
        strat.setEarnFees(defaultEarnFees);
        vault.withdrawFee = defaultWithdrawFee; //I've added this line in to set fees in the VH based pool as well as in the strat's vaultFees struct
        // vault.boostPoolAddress = strat.boostPoolAddress();
        
        _strats[_strat] = vid;
        _unpause(vid);
        emit AddVault(_strat);
    }
    
    //enables sharesTotal function on strategy
    function sharesTotal(address _strat) external view returns (uint) {
        uint vid = findvid(_strat);
        return totalSupply(vid);
    }
    function isStrat(address _strat) public view returns (bool) {
        return _strats[_strat] > 0;
    }
    function findvid(address _strat) public view returns (uint) {
        uint vid = _strats[_strat];
        require(vid > 0, "address is not a strategy on this VaultHealer"); //must revert here for security
        return vid;
    }
    
    function getEarnFees(uint _vid) public view returns (VaultFees memory) {
        VaultInfo storage vault = _vaultInfo[_vid];
        if (overrideDefaultEarnFees(_vid)) 
            return vault.strat.earnFees();
        else
            return defaultEarnFees;
    }
    
    function overrideDefaultEarnFees(uint vid) public view returns (bool) { // strategy's fee config doesn't change with the vaulthealer's default
        return _overrideDefaultEarnFees.get(vid);
    }
    function overrideDefaultWithdrawFee(uint vid) public view returns (bool) {
        return _overrideDefaultWithdrawFee.get(vid);
    }

     function setDefaultEarnFees(VaultFees calldata _earnFees) external onlyOwner {
        defaultEarnFees = _earnFees;
        emit SetDefaultEarnFees(_earnFees);
        
        for (uint i = 1; i < _vaultInfo.length; i++) {
            if (overrideDefaultEarnFees(i)) continue; //todo: optimize use of bitmap, like earn
            try _vaultInfo[i].strat.setEarnFees(_earnFees) {}
            catch { emit SetDefaultFail(i); }
        }
    }   
    function setEarnFees(uint _vid, VaultFees calldata _earnFees) external onlyOwner {
        _overrideDefaultEarnFees.set(_vid);
        _vaultInfo[_vid].strat.setEarnFees(_earnFees);
        emit SetEarnFees(_vid, _earnFees);
    }
    function resetEarnFees(uint _vid) external onlyOwner {
        _overrideDefaultEarnFees.unset(_vid);
        _vaultInfo[_vid].strat.setEarnFees(defaultEarnFees);
        emit ResetEarnFees(_vid);
    }
    
    function getWithdrawFee(uint _vid) public view returns (VaultFee memory) {
        return _vaultInfo[_vid].withdrawFee;
    }

    function setWithdrawFee(uint _vid, VaultFee calldata _withdrawFee) external onlyOwner {
        _overrideDefaultWithdrawFee.set(_vid);
        _vaultInfo[_vid].withdrawFee = _withdrawFee;
        emit SetWithdrawFee(_vid, _withdrawFee);
    }
    
    function earnAll() external nonReentrant {

        uint bucketLength = (_vaultInfo.length >> 8) + 1; // use one uint256 per 256 vaults

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i]; //earn unpaused vaults

            uint end = (i+1) << 8; // buckets end at multiples of 256
            if (_vaultInfo.length < end) end = _vaultInfo.length; //or if less, the final pool
            for (uint j = i << 8; j < end; j++) {
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    try _vaultInfo[j].strat.earn(_msgSender()) {}
                    catch {}
                }
                earnMap >>= 1; //shift away the used bit
                if (earnMap == 0) break;
            }
        }
    }
    
    function earnSome(uint256[] memory vids) external nonReentrant {

        uint bucketLength = (_vaultInfo.length >> 8) + 1; // use one uint256 per 256 vaults
        uint256[] memory selBuckets = new uint256[](bucketLength); //BitMap of selected vids

        for (uint i; i < vids.length; i++) { //memory bitmap of all selected vids
            uint vid = vids[i];
            if (vid <= _vaultInfo.length)
                selBuckets[vid >> 8] |= 1 << (vid & 0xff); //set bit for selected vid
        }

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i] & selBuckets[i]; //earn selected, unpaused vaults

            uint end = (i+1) << 8; // buckets end at multiples of 256
            for (uint j = i << 8; j < end; j++) {//0-255, 256-511, ...
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    try _vaultInfo[j].strat.earn(_msgSender()) {}
                    catch {}
                }
                earnMap >>= 1; //shift away the used bit
                if (earnMap == 0) break; //if bucket is empty, done with bucket
            }
        }
    }
    function earn(uint256 vid) external whenNotPaused(vid) nonReentrant {
        _vaultInfo[vid].strat.earn(_msgSender());
    }

    //Like OpenZeppelin Pausable, but centralized here at the vaulthealer
    ///////////////////////
    function pause(uint vid) external onlyOwner {
        _pause(vid);
    }
    function unpause(uint vid) external onlyOwner {
        _unpause(vid);
    }
    function panic(uint vid) external onlyOwner {
        _pause(vid);
        _vaultInfo[vid].strat.panic();
    }
    function unpanic(uint vid) external onlyOwner {
        _unpause(vid);
        _vaultInfo[vid].strat.unpanic();
    }
    
    function paused(address _strat) external view returns (bool) {
        return paused(findvid(_strat));
    }
    function paused(uint vid) public view returns (bool) {
        return !pauseMap.get(vid);
    }
    modifier whenNotPaused(uint vid) {
        require(!paused(vid), "Pausable: paused");
        _;
    }
    modifier whenPaused(uint vid) {
        require(paused(vid), "Pausable: not paused");
        _;
    }
    function _pause(uint vid) internal virtual whenNotPaused(vid) {
        pauseMap.unset(vid);
        emit Paused(vid);
    }
    function _unpause(uint vid) internal virtual whenPaused(vid) {
        require(vid > 0 && vid < _vaultInfo.length, "invalid vid");
        pauseMap.set(vid);
        emit Unpaused(vid);
    }
}
