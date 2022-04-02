// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "./libraries/Cavendish.sol";
import "./interfaces/IVaultHealer.sol";
import "./VaultFeeManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./VaultHealerAuth.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./libraries/VaultChonk.sol";

abstract contract VaultHealerBase is ERC1155, IVaultHealer, ReentrancyGuard {

    uint constant PANIC_LOCK_DURATION = 6 hours;

    VaultFeeManager immutable public vaultFeeManager;
    VaultHealerAuth immutable public vhAuth;
    
    uint16 public numVaultsBase; //number of non-maximizer vaults

    mapping(uint => VaultInfo) public vaultInfo; // Info of each vault.
	mapping(uint => uint) private panicLockExpiry;

    constructor() {
        vhAuth = new VaultHealerAuth(msg.sender);
        vaultFeeManager = new VaultFeeManager(address(vhAuth));
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

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return ERC1155.supportsInterface(interfaceId) || interfaceId == type(IVaultHealer).interfaceId;
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

    //True values are the default behavior; call earn before deposit/withdraw
    function setAutoEarn(uint vid, bool earnBeforeDeposit, bool earnBeforeWithdraw) external auth requireValidVid(vid) {
        uint8 setting = earnBeforeDeposit ? 0 : 1;
        if (!earnBeforeWithdraw) setting += 2;
        vaultInfo[vid].noAutoEarn = setting;
        emit SetAutoEarn(vid, earnBeforeDeposit, earnBeforeWithdraw);
    }


//Like OpenZeppelin Pausable, but centralized here at the vaulthealer

    function pause(uint vid, bool panic) external auth whenNotPaused(vid) {
        if (panic) {
            uint expiry = panicLockExpiry[vid];
            if (expiry > block.timestamp) revert PanicCooldown(expiry);
            expiry = block.timestamp + PANIC_LOCK_DURATION;
            strat(vid).panic();
        }
        vaultInfo[vid].active = false;
        emit Paused(vid);
    }
    function unpause(uint vid) external auth requireValidVid(vid) {
        require(!vaultInfo[vid].active);
        vaultInfo[vid].active = true;
        strat(vid).unpanic();
        emit Unpaused(vid);
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
