// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/OpenZeppelin.sol";

import "./libs/Vault.sol";
import "./libs/IStrategy.sol";
import "./libs/IVaultHealer.sol";
import "./libs/IVaultFeeManager.sol";
import "hardhat/console.sol";

abstract contract VaultHealerBase is AccessControlEnumerable, ERC1155SupplyUpgradeable, IVaultHealerMain {
    using SafeERC20 for IERC20;
    using BitMaps for BitMaps.BitMap;

    uint constant PANIC_LOCK_DURATION = 6 hours;
    bytes32 constant PAUSER = keccak256("PAUSER");
    bytes32 constant STRATEGY = keccak256("STRATEGY");
    bytes32 constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 constant SETTINGS_SETTER = keccak256("SETTINGS_SETTER");
    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");

    IVaultFeeManager internal vaultFeeManager;
    Vault.Info[] internal _vaultInfo; // Info of each vault.
    BitMaps.BitMap internal pauseMap; //Boolean pause status for each vault; true == unpaused

    //vid for any of our strategies
    mapping(address => uint32) private _strats;
    uint256 internal _lock = type(uint32).max;

    event AddVault(address indexed strat);
    event SetVaultFeeManager(IVaultFeeManager indexed _manager);
    event Paused(uint vid);
    event Unpaused(uint vid);

    constructor(address _owner) {
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(VAULT_ADDER, _owner);
        _setRoleAdmin(STRATEGY, VAULT_ADDER);
        _setupRole(PAUSER, _owner);
        _setupRole(FEE_SETTER, _owner);
        _setupRole(SETTINGS_SETTER, _owner);
        _vaultInfo.push(); //so uninitialized vid variables (vid 0) can be assumed as invalid
    }
    function setVaultFeeManager(IVaultFeeManager _manager) external onlyRole(FEE_SETTER) {
        vaultFeeManager = _manager;
    }

    /**
     * @dev Add a new want to the vault. Can only be called by the owner.
     */

    function addVault(address _strat) internal virtual returns (uint vid) {
        require(!hasRole(STRATEGY, _strat)/*, "Existing strategy"*/);
        grantRole(STRATEGY, _strat); //requires msg.sender is VAULT_ADDER

        IStrategy strat_ = IStrategy(_strat);
        require(_vaultInfo.length < type(uint32).max); //absurd number of vaults
        vid = _vaultInfo.length;
        _vaultInfo.push();
        Vault.Info storage vault = _vaultInfo[vid];
        IERC20 _want = strat_.wantToken();
        vault.want = _want;
        require(_want.totalSupply() <= type(uint112).max);
        //vault.router = strat.router();
        vault.lastEarnBlock = uint32(block.number);
        vault.minBlocksBetweenEarns = 10;
        vault.targetVid = uint32(_strats[address(strat_.targetVault())]);
        pauseMap.set(vid); //uninitialized vaults are paused; this unpauses
        
        _strats[_strat] = uint32(vid);
        emit AddVault(_strat);
    }

    modifier nonReentrant() {
        require(_lock == type(uint32).max, "reentrancy");
        _lock = 0;
        _;
        _lock = type(uint32).max;
    }

    modifier reentrantOnlyByStrategy(uint vid) {
        uint lock = _lock; //saves initial lock state
        
        require(lock == type(uint32).max || msg.sender == address(strat(lock)), "reentrancy/!strat"); //must either not be entered, or caller is the active strategy
        _lock = vid; //this vid's strategy may reenter
        _;
        _lock = lock; //restore initial state
    }

    function findVid(address _strat) internal view returns (uint32 vid) {
        vid = _strats[_strat];
        require(vid > 0/*, "address is not a strategy on this VaultHealer"*/); //must revert here for security
    }
    function setSettings(uint vid, Vault.Settings calldata _settings) external onlyRole(SETTINGS_SETTER) {
        strat(vid).setSettings(_settings);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC1155Upgradeable) returns (bool) {
        return AccessControlEnumerable.supportsInterface(interfaceId) || ERC1155Upgradeable.supportsInterface(interfaceId) || interfaceId == type(IVaultHealer).interfaceId;
    }

    function strat(uint _vid) internal virtual view returns (IStrategy);

//Like OpenZeppelin Pausable, but centralized here at the vaulthealer

    function pause(uint vid) external onlyRole("PAUSER") {
        _pause(vid);
    }
    function unpause(uint vid) external onlyRole("PAUSER") {
        _unpause(vid);
    }
    function panic(uint vid) external onlyRole("PAUSER") {
        require (_vaultInfo[vid].panicLockExpiry < block.timestamp, "panic once per 6 hours");
        _vaultInfo[vid].panicLockExpiry = uint40(block.timestamp + PANIC_LOCK_DURATION);
        _pause(vid);
        strat(vid).panic();
    }
    function unpanic(uint vid) external onlyRole("PAUSER") {
        _unpause(vid);
        strat(vid).unpanic();
    }
    function paused(uint vid) internal view returns (bool) {
        return !pauseMap.get(vid);
    }
    modifier whenNotPaused(uint vid) {
        require(!paused(vid), "VH: paused");
        _;
    }
    function _pause(uint vid) internal whenNotPaused(vid) {
        pauseMap.unset(vid);
        emit Paused(vid);
    }
    function _unpause(uint vid) internal {
        require(paused(vid) && vid > 0 && vid < _vaultInfo.length);
        pauseMap.set(vid);
        emit Unpaused(vid);
    }
}
