// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBase.sol";

//Like OpenZeppelin Pausable, but centralized here at the vaulthealer
abstract contract VaultHealerPause is VaultHealerBase {
    using BitMaps for BitMaps.BitMap;
    
    uint constant PANIC_LOCK_DURATION = 6 hours;
    bytes32 public constant PAUSER = keccak256("PAUSER");

    BitMaps.BitMap internal pauseMap; //Boolean pause status for each vault; true == unpaused

    event Paused(uint vid);
    event Unpaused(uint vid);

    constructor(address _owner) {
        _setupRole(PAUSER, _owner);
    }

    function addVault(address _strat, uint minBlocksBetweenEarns) public virtual override returns (uint vid) {
        vid = super.addVault(_strat, minBlocksBetweenEarns);
        pauseMap.set(vid); //uninitialized vaults are paused; this unpauses
    }    

    function pause(uint vid) external onlyRole("PAUSER") {
        _pause(vid);
    }
    function unpause(uint vid) external onlyRole("PAUSER") {
        _unpause(vid);
    }
    function panic(uint vid) external onlyRole("PAUSER") {
        require (_vaultInfo[vid].panicLockExpiry < block.timestamp, "panic once per 6 hours");
        _vaultInfo[vid].panicLockExpiry = block.timestamp + PANIC_LOCK_DURATION;
        _pause(vid);
        _vaultInfo[vid].strat.panic();
    }
    function unpanic(uint vid) external onlyRole("PAUSER") {
        _unpause(vid);
        _vaultInfo[vid].strat.unpanic();
    }
    function paused() external view returns (bool) {
        return paused(findVid(msg.sender));
    }
    
    function paused(address _strat) external view returns (bool) {
        return paused(findVid(_strat));
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
    function _pause(uint vid) internal whenNotPaused(vid) {
        pauseMap.unset(vid);
        emit Paused(vid);
    }
    function _unpause(uint vid) internal whenPaused(vid) {
        require(vid > 0 && vid < _vaultInfo.length, "invalid vid");
        pauseMap.set(vid);
        emit Unpaused(vid);
    }
}