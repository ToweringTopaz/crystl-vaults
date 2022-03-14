// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "./libraries/Cavendish.sol";
import "./interfaces/IVaultHealer.sol";
import "./interfaces/IVaultFeeManager.sol";
//import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract VaultHealerBase is AccessControl, ERC1155Supply, /*ERC2771Context,*/ IVaultHealer, ReentrancyGuard {

    uint constant PANIC_LOCK_DURATION = 6 hours;
    bytes32 constant PAUSER = keccak256("PAUSER");
    //bytes32 constant STRATEGY = keccak256("STRATEGY");
    bytes32 constant VAULT_ADDER = keccak256("VAULT_ADDER");
    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");

    IVaultFeeManager public vaultFeeManager;
    uint16 public numVaultsBase = 0; //number of non-maximizer vaults

    mapping(uint => VaultInfo) public vaultInfo; // Info of each vault.
	mapping(uint => uint) public panicLockExpiry;



    constructor(address _owner) {
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(VAULT_ADDER, _owner);
        _setupRole(PAUSER, _owner);
        _setupRole(FEE_SETTER, _owner);
    }


    function setVaultFeeManager(IVaultFeeManager _manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vaultFeeManager = _manager;
        emit SetVaultFeeManager(_manager);
    }


    function createVault(address _implementation, bytes calldata data) external onlyRole(VAULT_ADDER) nonReentrant returns (uint16 vid) {
        vid = numVaultsBase + 1;
        numVaultsBase = vid;
        addVault(vid, _implementation, data);
    }

	
    function createMaximizer(uint targetVid, bytes calldata data) external requireValidVid(targetVid) onlyRole(VAULT_ADDER) nonReentrant returns (uint vid) {
		if (targetVid >= 2**208) revert MaximizerTooDeep(targetVid);
        VaultInfo storage targetVault = vaultInfo[targetVid];
        uint16 nonce = targetVault.numMaximizers + 1;
        vid = (targetVid << 16) | nonce;
        targetVault.numMaximizers = nonce;
        addVault(vid, address(strat(targetVid).getMaximizerImplementation()), data);
    }


    function addVault(uint256 vid, address implementation, bytes calldata data) internal {

        IStrategy _strat = IStrategy(Cavendish.clone(implementation, bytes32(uint(vid))));
        _strat.initialize(abi.encodePacked(vid, data));
        vaultInfo[vid].want = _strat.wantToken();
        vaultInfo[vid].active = true; //uninitialized vaults are paused; this unpauses
        emit AddVault(vid);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC1155) returns (bool) {
        return AccessControl.supportsInterface(interfaceId) || ERC1155.supportsInterface(interfaceId) || interfaceId == type(IVaultHealer).interfaceId;
    }

    //Computes the strategy address for any vid based on this contract's address and the vid's numeric value
    function strat(uint _vid) public view returns (IStrategy) {
        return IStrategy(Cavendish.computeAddress(bytes32(_vid)));
    }

    //Requires that a vid represents some deployed vault
    modifier requireValidVid(uint vid) {
        _requireValidVid(vid);
        _;
    }
    function _requireValidVid(uint vid) internal view {
        uint subVid = vid & 0xffff;
        if (subVid == 0 || subVid > (subVid == vid ? numVaultsBase : vaultInfo[vid >> 16].numMaximizers))
			revert VidOutOfRange(vid);
    }
	
/*
   function _msgData() internal view virtual override(Context, ERC2771Context) returns (bytes calldata) { return ERC2771Context._msgData(); }
   function _msgSender() internal view virtual override(Context, ERC2771Context) returns (address) { return ERC2771Context._msgSender(); }
*/

    //True values are the default behavior; call earn before deposit/withdraw
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
        require(!vaultInfo[vid].active);
        vaultInfo[vid].active = true;
        emit Unpaused(vid);
    }

	function panic(uint vid) external {
        uint expiry = panicLockExpiry[vid];
        if (expiry > block.timestamp) revert PanicCooldown(expiry);
        expiry = block.timestamp + PANIC_LOCK_DURATION;
        pause(vid);
        strat(vid).panic();
    }
    function unpanic(uint vid) external {
        unpause(vid);
        strat(vid).unpanic();
    }
    function paused(uint vid) external view returns (bool) {
        return !vaultInfo[vid].active;
    }
    modifier whenNotPaused(uint vid) {
        if (!vaultInfo[vid].active) revert PausedError(vid);
        _;
    }

    fallback() external {
        Cavendish._fallback();
        revert InvalidFallback();
    }
}
