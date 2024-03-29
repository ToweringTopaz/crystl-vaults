// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "./libraries/Cavendish.sol";
import "./interfaces/IVaultHealer.sol";
import "./VaultFeeManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./VaultHealerAuth.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./libraries/VaultChonk.sol";

abstract contract VaultHealerBase is IVaultHealer, ReentrancyGuard {

    uint constant PANIC_LOCK_DURATION = 6 hours;

    IVaultFeeManager immutable public vaultFeeManager;
    VaultHealerAuth immutable public vhAuth;
    
    uint16 public numVaultsBase; //number of non-maximizer vaults

    mapping(uint => VaultInfo) public vaultInfo; // Info of each vault.
	mapping(uint => uint) private panicLockExpiry;

    constructor(address _vhAuth, address _feeMan) {
        vhAuth = VaultHealerAuth(_vhAuth);
        vaultFeeManager = IVaultFeeManager(_feeMan);
    }

    modifier auth {
        _auth();
        _;
    }
    function _auth() view private {
        bytes4 selector = bytes4(msg.data);
        if (!IAccessControl(vhAuth).hasRole(selector, msg.sender)) revert RestrictedFunction(selector);
    }

    function createVault(IStrategy _implementation, bytes calldata data) external auth nonReentrant returns (uint16 vid) {
        vid = numVaultsBase + 1;
        numVaultsBase = vid;
        VaultChonk.createVault(vaultInfo, vid, _implementation, data);
    }
	
    function createMaximizer(uint targetVid, bytes calldata data) external requireValidVid(targetVid) auth nonReentrant returns (uint vid) {
        return VaultChonk.createMaximizer(vaultInfo, targetVid, data);
    }

    //Computes the strategy address for any vid based on this contract's address and the vid's numeric value
    function strat(uint _vid) public view returns (IStrategy) {
        return VaultChonk.strat(_vid);
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

    //True values are the default behavior; call earn before deposit/withdraw
    function setAutoEarn(uint vid, bool earnBeforeDeposit, bool earnBeforeWithdraw) external auth requireValidVid(vid) {
        vaultInfo[vid].noAutoEarn = (earnBeforeDeposit ? 0 : 1) | (earnBeforeWithdraw ? 0 : 2);
        emit SetAutoEarn(vid, earnBeforeDeposit, earnBeforeWithdraw);
    }

//Like OpenZeppelin Pausable, but centralized here at the vaulthealer

    function pause(uint vid, bool panic) external auth requireValidVid(vid) {
        if (vaultInfo[vid].active) { //use direct variable; paused(vid) also may be true due to maximizer
            if (panic) {
                uint expiry = panicLockExpiry[vid];
                if (expiry > block.timestamp) revert PanicCooldown(expiry);
                expiry = block.timestamp + PANIC_LOCK_DURATION;
                strat(vid).panic();
            }
            vaultInfo[vid].active = false;
            emit Paused(vid);
        }
    }
    function unpause(uint vid) external auth requireValidVid(vid) {
        if ((vid >> 16) > 0 && paused(vid >> 16)) revert PausedError(vid >> 16); // if maximizer's target is paused, it must be unpaused first
        if (!vaultInfo[vid].active) { //use direct variable
            vaultInfo[vid].active = true;
            strat(vid).unpanic();
            emit Unpaused(vid);
        }
    }
    function paused(uint vid) public view returns (bool) {
        return !vaultInfo[vid].active || ((vid >> 16) > 0 && paused(vid >> 16));
    }
    function paused(uint[] calldata vids) external view returns (bytes memory pausedArray) {
        
        uint len = vids.length;
        pausedArray = new bytes(len);

        for (uint i; i < len; i++) {
            pausedArray[i] = paused(vids[i]) ? bytes1(0x01) : bytes1(0x00);
        }        
    }
    modifier whenPaused(uint vid) {
        if (!paused(vid)) revert PausedError(vid);
        _;
    }
    modifier whenNotPaused(uint vid) {
        if (paused(vid)) revert PausedError(vid);
        _;
    }

    fallback() external {
        Cavendish._fallback();
        revert InvalidFallback();
    }
}
