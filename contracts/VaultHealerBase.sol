// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./libs/Vault.sol";
import "./libs/IStrategy.sol";
import "./libs/IVaultHealer.sol";
import "./libs/IVaultFeeManager.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

abstract contract VaultHealerBase is AccessControlEnumerable, ERC1155SupplyUpgradeable, IVaultHealerMain {
    using SafeERC20 for IERC20;
    using BitMaps for BitMaps.BitMap;

    uint constant PANIC_LOCK_DURATION = 6 hours;

    IVaultFeeManager public vaultFeeManager;
    mapping(address => Vault.Info) internal _vaultInfo; // Info of each vault.
    bool public vaultsPausedByDefault; //Vaults are paused when first created?

    //vid for any of our strategies
    mapping(IStrategy => uint32) private _strats;
    uint256 internal _lock = type(uint32).max;

    event AddVault(IStrategy indexed strat);

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
        require(oldAccess != Vault.Access.STRATEGY && oldAccess != Vault.Access.IMPLEMENTATION && _access != Vault.A);
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

    function createVault(address _implementation, bytes calldata data) external returns (uint vid) {
        vid = _vaultInfo.length;
        Vault.Info storage vault = _vaultInfo[vid];

        require(vid < 2**32, "too many vaults"); //absurd number of vaults
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
