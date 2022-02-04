// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libraries/Vault.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IVaultHealer.sol";
import "./interfaces/IVaultFeeManager.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

abstract contract VaultHealerBase is AccessControlEnumerable, ERC1155Supply, IVaultHealerMain {
    using BitMaps for BitMaps.BitMap;

    uint constant PANIC_LOCK_DURATION = 6 hours;
    bytes32 constant PAUSER = keccak256("PAUSER");
    bytes32 constant STRATEGY = keccak256("STRATEGY");
    bytes32 constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");

    IVaultFeeManager public vaultFeeManager;
    Vault.Info[] internal _vaultInfo; // Info of each vault.
    BitMaps.BitMap pauseMap; //true for unpaused vaults;

    //vid for any of our strategies
    mapping(IStrategy => uint32) private _strats;
    uint256 internal _lock = type(uint32).max;

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
        _vaultInfo.push(); //so uninitialized vid variables (vid 0) can be assumed as invalid
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
        
        _vaultInfo.push();
        
        IERC20 want = _strat.wantToken();
        vault.want = want;

        require(want.totalSupply() <= type(uint112).max, "incompatible total supply");
        pauseMap.set(vid); //uninitialized vaults are paused; this unpauses
        
        _strats[_strat] = uint32(vid);
        emit AddVault(vid);
    }

    modifier nonReentrant() {
        require(_lock == type(uint32).max, "reentrancy");
        _lock = 0;
        _;
        _lock = type(uint32).max;
    }

    modifier reentrantOnlyByStrategy(uint vid) {
        uint lock = _lock; //saves initial lock state

        require(lock == type(uint32).max || strat(lock) == IStrategy(msg.sender), "reentrancy/!strat"); //must either not be entered, or caller is the active strategy
        _lock = vid; //this vid's strategy may reenter
        _;
        _lock = lock; //restore initial state
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC1155) returns (bool) {
        return AccessControlEnumerable.supportsInterface(interfaceId) || ERC1155.supportsInterface(interfaceId) || interfaceId == type(IVaultHealer).interfaceId;
    }


    function strat(uint _vid) public view returns (IStrategy) {
        require(_vid > 0 && _vid < 2**32, "VH: invalid vid");
        bytes memory data;
        if (_vid < 0x80)           data = abi.encodePacked(bytes2(0xd694), address(this), uint8(_vid));
        else if (_vid < 0x100)     data = abi.encodePacked(bytes2(0xd794), address(this), bytes1(0x81), uint8(_vid));
        else if (_vid < 0x10000)   data = abi.encodePacked(bytes2(0xd894), address(this), bytes1(0x82), uint16(_vid));
        else if (_vid < 0x1000000) data = abi.encodePacked(bytes2(0xd994), address(this), bytes1(0x83), uint24(_vid));
        else                       data = abi.encodePacked(bytes2(0xda94), address(this), bytes1(0x84), uint32(_vid));
        return IStrategy(address(uint160(uint256(keccak256(data)))));
    }


//Like OpenZeppelin Pausable, but centralized here at the vaulthealer

    function pause(uint vid) public onlyRole("PAUSER") whenNotPaused(vid) {
        pauseMap.unset(vid);
        emit Paused(vid);
    }
    function unpause(uint vid) public onlyRole("PAUSER") {
        require(paused(vid) && vid > 0 && vid < _vaultInfo.length);
        pauseMap.set(vid);
        emit Unpaused(vid);
    }
    function panic(uint vid) external {
        require (_vaultInfo[vid].panicLockExpiry < block.timestamp, "panic once per 6 hours");
        _vaultInfo[vid].panicLockExpiry = uint40(block.timestamp + PANIC_LOCK_DURATION);
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
