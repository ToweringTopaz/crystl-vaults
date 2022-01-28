// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBase.sol";

//For calling the earn function
abstract contract VaultHealerEarn is VaultHealerBase {

    event Earned(uint256 indexed vid, uint256 wantAmountEarned);
    
    function earnSome(uint256[] calldata vids) external nonReentrant {
        uint bucketLength = (_vaultInfo.length >> 8) + 1; // use one uint256 per 256 vaults
        uint256[] memory selBuckets = new uint256[](bucketLength); //BitMap of selected vids

        for (uint i; i < vids.length; i++) { //memory bitmap of all selected vids
            uint vid = vids[i];
            if (vid <= _vaultInfo.length)
                selBuckets[vid >> 8] |= 1 << (vid & 0xff); //set bit for selected vid
        }

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i] & selBuckets[i]; //earn selected, unpaused vaults

            uint end = (i+1) << 8; // buckets end at multiples of 256
            for (uint j = i << 8; j < end; j++) {//0-255, 256-511, ...
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    _tryEarn(j);
                }
                earnMap >>= 1; //shift away the used bit

                if (earnMap == 0) break; //if bucket is empty, done with bucket
            }
        }
    }
    function earn(uint256 vid) external whenNotPaused(vid) nonReentrant {
        _doEarn(vid);
    }

    function _tryEarn(uint256 vid) private {
        Vault.Info storage vault = _vaultInfo[vid];
        uint32 lastEarnBlock = vault.lastEarnBlock;
        uint32 interval = vault.minBlocksBetweenEarns;

        uint lock = _lock;
        _lock = vid; //permit reentrant calls by this vault only
        if (block.number > lastEarnBlock + interval) {
            try strat(vid).earn(vaultFeeManager.getEarnFees(vid)) returns (bool success, uint256 wantLockedTotal) {
                if (success) {
                    lastEarnBlock = uint32(block.number);
                    decrementMinBlocksBetweenEarns(vault, interval);  //Decrease number of blocks between earns by 1 if successful (settings.dust)
                } else {
                    increaseMinBlocksBetweenEarns(vault, interval); //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
                }
                updateWantLockedLast(vault, vid, wantLockedTotal);
            } catch {
                increaseMinBlocksBetweenEarns(vault, interval);
            }
        }
        _lock = lock; //reset reentrancy state
    }

    //performs earn even if it's not been long enough
    function _doEarn(uint256 vid) internal {
        Vault.Info storage vault = _vaultInfo[vid];
        uint32 lastEarnBlock = vault.lastEarnBlock;
        uint32 interval = vault.minBlocksBetweenEarns;
        
        if (lastEarnBlock == block.number) return; //earn only once per block ever
        uint lock = _lock;
        _lock = vid; //permit reentrant calls by this vault only
        try strat(vid).earn(vaultFeeManager.getEarnFees(vid)) returns (bool success, uint256 wantLockedTotal) {
            if (success) {
                vault.lastEarnBlock = uint32(block.number);
                if (block.number > lastEarnBlock + interval) {
                    decrementMinBlocksBetweenEarns(vault, interval); //Decrease number of blocks between earns by 1 if successful (settings.dust)
                }
            } else if (block.number > lastEarnBlock + interval) {
                increaseMinBlocksBetweenEarns(vault, interval); //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
            }
            updateWantLockedLast(vault, vid, wantLockedTotal);
        } catch {
            if (block.number > vault.lastEarnBlock + interval) {
                increaseMinBlocksBetweenEarns(vault, interval);
            }
        }
        _lock = lock; //reset reentrancy state
    }
    function updateWantLockedLast(Vault.Info storage vault, uint vid, uint wantLockedTotal) private {
        if (wantLockedTotal > vault.wantLockedLastUpdate) {
            require(wantLockedTotal < type(uint112).max, "VH: wantLockedTotal overflow");
            emit Earned(vid, wantLockedTotal - vault.wantLockedLastUpdate);
            vault.wantLockedLastUpdate = uint112(wantLockedTotal);
        }
    }
    function decrementMinBlocksBetweenEarns(Vault.Info storage vault, uint32 oldInterval) private {
        if (oldInterval > 1) vault.minBlocksBetweenEarns = oldInterval - 1;
    }

    function increaseMinBlocksBetweenEarns(Vault.Info storage vault, uint oldInterval) private {
        vault.minBlocksBetweenEarns = uint32(oldInterval * 21 / 20 + 1); //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
    }
}