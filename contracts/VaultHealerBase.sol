// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/OpenZeppelin.sol";

import "./libs/Vault.sol";
import "./libs/IStrategy.sol";
import "./libs/IVaultHealer.sol";
import "./libs/IVaultFeeManager.sol";

abstract contract VaultHealerBase is ERC1155SupplyUpgradeable, IVaultHealerMain {

    uint constant PANIC_LOCK_DURATION = 6 hours;

    IVaultFeeManager public vaultFeeManager;
    mapping(address => Vault.Info) internal _vaultInfo; // Info of each vault.
    bool public vaultsPausedByDefault; //Vaults are paused when first created?

    uint256 internal _lock = type(uint256).max;

    event SetVaultFeeManager(IVaultFeeManager indexed _manager);
    event Paused(IStrategy indexed vid);
    event Unpaused(IStrategy indexed vid);
    event SetAccount(address indexed account, Vault.Access access);

    constructor() {

    }
    function setVaultFeeManager(IVaultFeeManager _manager) external onlyTreasurer {
        vaultFeeManager = _manager;
        emit SetVaultFeeManager(_manager);
    }
    function setAccess(address _account, Vault.Access _access) external {
        Vault.Access oldAccess = access[_account];
        Vault.Access operatorAccess = access[msg.sender];
        require(oldAccess != Vault.Access.STRATEGY && oldAccess != Vault.Access.IMPLEMENTATION && _access != Vault.A)
    }
    modifier onlyOwner {
        require(_vaultInfo[msg.sender].access >= Vault.Access.OWNER, "VH: only owner");
        _;
    }
    modifier onlyAdmin {
        require(_vaultInfo[msg.sender].access >= Vault.Access.ADMIN, "VH: only admin");
        _;
    }
    modifier onlyPauser {
        require(access[msg.sender].pauser, "VH: only pauser");
        _;
    }
    modifier onlyTester {
        require(access[msg.sender].tester, "VH: only tester");
        _;
    }
    /**
     * @dev Add a new want to the vault. Can only be called by the owner.
     */


    function addVault(IStrategy _strat) internal virtual returns (uint vid) {
        Vault.Info storage vault = _vaultInfo[_strat];
        IERC20 _want = _strat.wantToken();
        vault.want = _want;
        require(_want.totalSupply() <= type(uint112).max);
        vault.targetVid = _strat.targetVid();

        vault.exists = true;
        if (!vaultsPausedByDefault) vault.unpaused = true;
        emit AddVault(_strat);
    }

    modifier nonReentrant() {
        require(_lock == type(uint256).max, "reentrancy");
        _lock = 0;
        _;
        _lock = type(address).max;
    }

    modifier reentrantOnlyByStrategy(address vid) {
        uint lock = _lock; //saves initial lock state

        require(lock == type(uint256).max || msg.sender == address(lock), "reentrancy/!strat"); //must either not be entered, or caller is the active strategy
        _lock = vid; //this vid's strategy may reenter
        _;
        _lock = lock; //restore initial state
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC1155Upgradeable) returns (bool) {
        return AccessControlEnumerable.supportsInterface(interfaceId) || ERC1155Upgradeable.supportsInterface(interfaceId) || interfaceId == type(IVaultHealer).interfaceId;
    }

//Like OpenZeppelin Pausable, but centralized here at the vaulthealer

    function pause(address vid) external onlyPauser {
        _pause(vid);
    }
    function unpause(address vid) external onlyPauser {
        _unpause(vid);
    }
    function panic(address vid) external onlyPauser {
        require (_vaultInfo[vid].panicLockExpiry < block.timestamp, "panic once per 6 hours");
        _vaultInfo[vid].panicLockExpiry = uint40(block.timestamp + PANIC_LOCK_DURATION);
        _pause(vid);
        IStrategy(vid).panic();
    }
    function unpanic(address vid) external onlyPauser {
        _unpause(vid);
        strat(vid).unpanic();
    }
    function paused(address vid) public view returns (bool) {
        return !_vaultInfo[vid].unpaused;
    }
    modifier whenNotPaused(address vid) {
        require(!paused(vid) || _vaultInfo[msg.sender].unpaused, "VH: paused");
        _;
    }
    function _pause(address vid) internal whenNotPaused(vid) {
        _vaultInfo[vid].unpaused = false;
        emit Paused(vid);
    }
    function _unpause(address vid) internal {
        require(paused(vid) && vid > 0 && vid < _vaultInfo.length);
        pauseMap.set(vid);
        emit Unpaused(vid);
    }
}
