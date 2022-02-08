// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./Cavendish.sol";
import "./libraries/Vault.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IVaultHealer.sol";
import "./interfaces/IVaultFeeManager.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

abstract contract VaultHealerBase is Cavendish, AccessControlEnumerable, ERC1155Supply, IVaultHealerMain {

    using BitMaps for BitMaps.BitMap;

    uint constant MAX_MAXIMIZERS = 1024;
    uint constant PANIC_LOCK_DURATION = 6 hours;
    bytes32 constant PAUSER = keccak256("PAUSER");
    bytes32 constant STRATEGY = keccak256("STRATEGY");
    bytes32 constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");

    IVaultFeeManager public vaultFeeManager;

    mapping(uint => Vault.Info) public vaultInfo; // Info of each vault.
    mapping(address => mapping(uint => Vault.User)) internal vaultUser;
    uint32 public nextVid = 1; //first unused vid (vid 0 means null/invalid)

    BitMaps.BitMap pauseMap; //true for unpaused vaults;

    uint internal _lock = type(uint).max;

    event AddVault(uint indexed vid);

    event SetVaultFeeManager(IVaultFeeManager indexed _manager);
    event Paused(uint indexed vid);
    event Unpaused(uint indexed vid);

    constructor(address _owner) {
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(VAULT_ADDER, _owner);
        _setRoleAdmin(STRATEGY, VAULT_ADDER);
        _setupRole(PAUSER, _owner);
        _setupRole(FEE_SETTER, _owner);
    }

    function setVaultFeeManager(IVaultFeeManager _manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vaultFeeManager = _manager;
        emit SetVaultFeeManager(_manager);
    }
    /**
     * @dev Add a new want to the vault. Can only be called by the owner.
     */

    function createVault(address _implementation, bytes calldata data) external returns (uint vid) {
        vid = _vaultInfo.length;
        Vault.Info storage vault = _vaultInfo[vid];

        require(vid < type(uint32).max, "too many vaults"); //absurd number of vaults
        IStrategy _strat = IStrategy(Clones.clone(_implementation));
        assert(_strat == strat(vid));
        
        _strat.initialize(data);
        
        grantRole(STRATEGY, address(_strat)); //requires msg.sender is VAULT_ADDER
        

        IERC20 want = _strat.wantToken();
        vault.want = want;

        require(want.totalSupply() <= type(uint112).max, "incompatible total supply");
        pauseMap.set(vid); //uninitialized vaults are paused; this unpauses
        
        emit AddVault(vid);
    }

    function createMaximizer(uint targetVid, bytes calldata data) external requireValidVid(targetVid) returns (uint vid) {
        Vault.Info storage targetVault = vaultInfo[vid];
        require(targetVault.numMaximizers <= MAX_MAXIMIZERS, "VH: too many maximizers on this vault");
        vid = (targetVid << 32) + targetVault.numMaximizers;

        IStrategy targetStrat = strat(vid);

        IStrategy _strat = IStrategy(clone(address(targetStrat.getMaximizerImplementation()), STRATEGY ^ bytes32(vid)));
        assert(_strat == strat(vid));
        
        _strat.initialize(data);
        
        grantRole(STRATEGY, address(_strat)); //requires msg.sender is VAULT_ADDER
        targetVault.numMaximizers++;
        
        IERC20 want = _strat.wantToken();
        vaultInfo[vid].want = want;

        emit AddVault(vid);
    }

    modifier nonReentrant() {
        require(_lock == type(uint).max, "reentrancy");
        _lock = 0;
        _;
        _lock = type(uint).max;
    }

    modifier reentrantOnlyByStrategy(uint vid) {
        uint lock = _lock; //saves initial lock state

        require(lock == type(uint).max || strat(lock) == IStrategy(msg.sender), "reentrancy/!strat"); //must either not be entered, or caller is the active strategy
		
        _lock = vid; //this vid's strategy may reenter
        _;
        _lock = lock; //restore initial state
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC1155) returns (bool) {
        return AccessControlEnumerable.supportsInterface(interfaceId) || ERC1155.supportsInterface(interfaceId) || interfaceId == type(IVaultHealer).interfaceId;
    }


    function strat(uint _vid) public view returns (IStrategy) {
        return IStrategy(computeProxyAddress(bytes32(_vid) ^ STRATEGY));
    }

    modifier requireValidVid(uint vid) {
        _requireValidVid(vid);
        _;
    }

    function _requireValidVid(uint vid) internal view {
        if (vid == 0 || 
            ((vid >= nextVid) && 
                (vid >> 32 == 0 || 
                vid & 0xffffffff < vaultInfo[vid >> 32].numMaximizers)
            )
        ) revert("VH: nonexistent vid");
    }

//Like OpenZeppelin Pausable, but centralized here at the vaulthealer

    function pause(uint vid) public onlyRole("PAUSER") whenNotPaused(vid) {
        pauseMap.unset(vid);
        emit Paused(vid);
    }
    function unpause(uint vid) public onlyRole("PAUSER") {
        require(paused(vid) && vid > 0 && vid < nextVid);
        pauseMap.set(vid);
        emit Unpaused(vid);
    }
    

	function panic(uint vid) external {
        require (vaultInfo[vid].panicLockExpiry < block.timestamp, "panic once per 6 hours");
        vaultInfo[vid].panicLockExpiry = block.timestamp + PANIC_LOCK_DURATION;
        pause(vid);
        strat(vid).panic();
    }
    function unpanic(uint vid) external {
        unpause(vid);
        strat(vid).unpanic();
    }
    function paused(uint vid) public view returns (bool) {
        return !pauseMap.get(vid);
    }
    modifier whenNotPaused(uint vid) {
        require(!paused(vid), "VH: paused");
        _;
    }
}
