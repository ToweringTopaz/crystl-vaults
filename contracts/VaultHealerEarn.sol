// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBase.sol";

//For calling the earn function
abstract contract VaultHealerEarn is VaultHealerBase {

    event Earned(uint256 indexed vid, uint256 wantAmountEarned);
    
    function earn(uint256[] calldata vids) external nonReentrant {
        for (uint i; i < vids.length; i++) {
            uint vid = vids[i];
            if (paused(vid)) continue;
            _earn(vid);
        }
    }

    //performs earn even if it's not been long enough
    function _earn(uint256 vid) internal {
        Vault.Info storage vault = _vaultInfo[vid];
        uint32 lastEarnBlock = vault.lastEarnBlock;
        
        if (lastEarnBlock == block.number) return; //earn only once per block ever
        uint lock = _lock;
        _lock = vid; //permit reentrant calls by this vault only
        try strat(vid).earn(vaultFeeManager.getEarnFees(vid)) returns (bool success, uint256 wantLockedTotal) {
            if (success) {                
                updateWantLockedLast(vault, vid, wantLockedTotal);
            }
        } catch {}
        vault.lastEarnBlock = uint32(block.number);
        _lock = lock; //reset reentrancy state
    }
    function updateWantLockedLast(Vault.Info storage vault, uint vid, uint wantLockedTotal) private {
        uint wantLockedLastUpdate = vault.wantLockedLastUpdate;
        if (wantLockedTotal > wantLockedLastUpdate) {
            require(wantLockedTotal < type(uint112).max, "VH: wantLockedTotal overflow");
            emit Earned(vid, wantLockedTotal - wantLockedLastUpdate);
            vault.wantLockedLastUpdate = uint112(wantLockedTotal);
        }
    }
}