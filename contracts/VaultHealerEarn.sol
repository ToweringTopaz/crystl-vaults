// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerPause.sol";
import "./VaultHealerFees.sol";

//For calling the earn function
abstract contract VaultHealerEarn is VaultHealerPause, VaultHealerFees {

    function earnAll() external nonReentrant {

        VaultFees memory _defaultEarnFees = defaultEarnFees;
        uint bucketLength = (_vaultInfo.length >> 8) + 1; // use one uint256 per 256 vaults

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i]; //earn unpaused vaults
            uint feeMap = _overrideDefaultEarnFees._data[i];
            uint end = (i+1) << 8; // buckets end at multiples of 256
            if (_vaultInfo.length < end) end = _vaultInfo.length; //or if less, the final pool
            for (uint j = i << 8; j < end; j++) {
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    _tryEarn(i, feeMap & 1 > 0 ? _vaultInfo[i].earnFees : _defaultEarnFees);
                }
                earnMap >>= 1; //shift away the used bit
                feeMap >>= 1;

                if (earnMap == 0) break;
            }
        }
    }
    
    function earnSome(uint256[] memory vids) external nonReentrant {

        VaultFees memory _defaultEarnFees = defaultEarnFees;
        uint bucketLength = (_vaultInfo.length >> 8) + 1; // use one uint256 per 256 vaults
        uint256[] memory selBuckets = new uint256[](bucketLength); //BitMap of selected vids

        for (uint i; i < vids.length; i++) { //memory bitmap of all selected vids
            uint vid = vids[i];
            if (vid <= _vaultInfo.length)
                selBuckets[vid >> 8] |= 1 << (vid & 0xff); //set bit for selected vid
        }

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i] & selBuckets[i]; //earn selected, unpaused vaults
            uint feeMap = _overrideDefaultEarnFees._data[i];

            uint end = (i+1) << 8; // buckets end at multiples of 256
            for (uint j = i << 8; j < end; j++) {//0-255, 256-511, ...
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    _tryEarn(i, feeMap & 1 > 0 ? _vaultInfo[i].earnFees : _defaultEarnFees);
                }
                earnMap >>= 1; //shift away the used bit
                feeMap >>= 1;

                if (earnMap == 0) break; //if bucket is empty, done with bucket
            }
        }
    }
    function earn(uint256 vid) external whenNotPaused(vid) nonReentrant {
        _doEarn(vid);
    }

    function _tryEarn(uint256 vid, VaultFees memory _earnFees) private {
        VaultInfo storage vault = _vaultInfo[vid];
        uint interval = vault.minBlocksBetweenEarns;

        if (block.number > vault.lastEarnBlock + interval) {
            try vault.strat.earn(_msgSender(), _earnFees) returns (bool success) {
                if (success) {
                    vault.lastEarnBlock = block.number;
                    if (interval > 1) vault.minBlocksBetweenEarns = interval - 1; //Decrease number of blocks between earns by 1 if successful (settings.dust)
                } else {
                    vault.minBlocksBetweenEarns = interval * 21 / 20 + 1; //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
                }
            } catch {}
        }
    }

    //performs earn even if it's not been long enough
    function _doEarn(uint256 vid) internal {
        VaultInfo storage vault = _vaultInfo[vid];
        uint interval = vault.minBlocksBetweenEarns;   

        try vault.strat.earn(_msgSender(), overrideDefaultEarnFees(vid) ? _vaultInfo[vid].earnFees : defaultEarnFees) returns (bool success) {
            if (success) {
                vault.lastEarnBlock = block.number;
                if (interval > 1 && block.number > vault.lastEarnBlock + interval)
                    vault.minBlocksBetweenEarns = interval - 1; //Decrease number of blocks between earns by 1 if successful (settings.dust)
            } else if (block.number > vault.lastEarnBlock + interval) {
                vault.minBlocksBetweenEarns = interval * 21 / 20 + 1; //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
            }
        } catch {}     
    }
}