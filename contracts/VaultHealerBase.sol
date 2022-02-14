// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "./libraries/Cavendish.sol";
import "./interfaces/IVaultHealer.sol";
import "./interfaces/IVaultFeeManager.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "hardhat/console.sol";

abstract contract VaultHealerBase is AccessControlEnumerable, ERC1155Supply, ERC2771Context, IVaultHealer {

    uint constant MAX_MAXIMIZERS = type(uint32).max;
    uint constant PANIC_LOCK_DURATION = 6 hours;
    bytes32 constant PAUSER = keccak256("PAUSER");
    bytes32 constant STRATEGY = keccak256("STRATEGY");
    bytes32 constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");

    IVaultFeeManager public vaultFeeManager;

    mapping(uint => VaultInfo) public vaultInfo; // Info of each vault.

    uint32 public nextVid = 1; //first unused base vid (vid 0 means null/invalid)
    uint internal _lock = type(uint).max;


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


    function createVault(address _implementation, bytes calldata data) external onlyRole(VAULT_ADDER) returns (uint32 vid) {
        vid = nextVid;
        nextVid = vid + 1;
        addVault(vid, _implementation, data);
    }


    function createMaximizer(uint targetVid, bytes calldata data) external requireValidVid(targetVid) onlyRole(VAULT_ADDER) returns (uint vid) {
        require(targetVid < 2**192, "VH: maximizer too deep");
        VaultInfo storage targetVault = vaultInfo[targetVid];
        uint32 nonce = targetVault.numMaximizers + 1;
        require(nonce <= MAX_MAXIMIZERS, "VH: too many maximizers on this vault");
        vid = (targetVid << 16) + nonce;
        console.log(targetVid);
        console.log(targetVid << 16);
        console.log(nonce);
        console.log(vid);
        targetVault.numMaximizers = nonce + 1;
        addVault(vid, address(strat(targetVid).getMaximizerImplementation()), data);
    }


    function addVault(uint256 vid, address implementation, bytes calldata data) internal {

        IStrategy _strat = IStrategy(Cavendish.clone(implementation, bytes32(uint(vid))));
        _strat.initialize(abi.encodePacked(vid, data));
        grantRole(STRATEGY, address(_strat)); //requires msg.sender is VAULT_ADDER
        vaultInfo[vid].want = _strat.wantToken();
        vaultInfo[vid].active = true; //uninitialized vaults are paused; this unpauses
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
        return IStrategy(Cavendish.computeAddress(bytes32(_vid)));
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


   function _msgData() internal view virtual override(Context, ERC2771Context) returns (bytes calldata) { return ERC2771Context._msgData(); }
   function _msgSender() internal view virtual override(Context, ERC2771Context) returns (address) { return ERC2771Context._msgSender(); }

    //True values are the default behavior; call earn before deposit/withdraw?
    function setAutoEarn(uint vid, bool earnBeforeDeposit, bool earnBeforeWithdraw) external onlyRole("PAUSER") requireValidVid(vid) {
        uint8 setting = earnBeforeDeposit ? 0 : 1;
        if (!earnBeforeWithdraw) setting += 2;
        vaultInfo[vid].noAutoEarn = setting;
        emit SetAutoEarn(vid, earnBeforeDeposit, earnBeforeWithdraw);
    }


//Like OpenZeppelin Pausable, but centralized here at the vaulthealer

    function pause(uint vid) public onlyRole("PAUSER") whenNotPaused(vid) {
        vaultInfo[vid].active = false;
        emit Paused(vid);
    }
    function unpause(uint vid) public onlyRole("PAUSER") requireValidVid(vid) {
        require(paused(vid));
        vaultInfo[vid].active = true;
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
        return !vaultInfo[vid].active;
    }
    modifier whenNotPaused(uint vid) {
        require(!paused(vid), "VH: paused");
        _;
    }

    fallback() external {
        Cavendish._fallback();
        revert("VH: invalid call to fallback");
    }
}
