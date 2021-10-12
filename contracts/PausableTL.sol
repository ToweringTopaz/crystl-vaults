// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/Pausable.sol";

//This modifies the Pausable functions so that once paused, the contract may not be
//unpaused for six hours. This prevents the hypothetical situation where repeated 
//pause/unpause may cause token loss, as mentioned in the HashEx audit.
abstract contract PausableTL is Pausable {
    
    uint constant PAUSE_LOCK_DURATION = 6 hours;
    uint public pauseLockExpiry;
    
    function _pause() internal override {
        super._pause();
        pauseLockExpiry = block.timestamp + PAUSE_LOCK_DURATION;
    }
    function _unpause() internal override {
        require(pauseLockExpiry < block.timestamp, "Unpause is timelocked");
        super._unpause();
    }
}