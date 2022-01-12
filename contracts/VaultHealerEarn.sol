// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerPause.sol";
import "./VaultHealerFees.sol";
import "hardhat/console.sol";

//For calling the earn function
abstract contract VaultHealerEarn is VaultHealerPause, VaultHealerFees {

    event Earned(uint256 indexed vid, uint256 wantAmountEarned);

    function earnAll() external nonReentrant {

        Vault.Fees memory _defaultEarnFees = defaultEarnFees;
        uint bucketLength = (_vaultInfo.length >> 8) + 1; // use one uint256 per 256 vaults

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i]; //earn unpaused vaults
            uint feeMap = _overrideDefaultEarnFees._data[i];
            uint end = (i+1) << 8; // buckets end at multiples of 256
            if (_vaultInfo.length < end) end = _vaultInfo.length; //or if less, the final pool
            for (uint j = i << 8; j < end; j++) {
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    _tryEarn(j, feeMap & 1 > 0 ? _vaultInfo[i].earnFees : _defaultEarnFees);
                }
                earnMap >>= 1; //shift away the used bit
                feeMap >>= 1;

                if (earnMap == 0) break;
            }
        }
    }
    
    function earnSome(uint256[] calldata vids) external nonReentrant {
        Vault.Fees memory _defaultEarnFees = defaultEarnFees;
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
                    console.log("VHE - just before tryEarn");
                    _tryEarn(j, feeMap & 1 > 0 ? _vaultInfo[i].earnFees : _defaultEarnFees);
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

    function _tryEarn(uint256 vid, Vault.Fees memory _earnFees) private {
        Vault.Info storage vault = _vaultInfo[vid];
        uint32 interval = vault.minBlocksBetweenEarns;

        if (block.number > vault.lastEarnBlock + interval) {
            console.log("VHE - past first conditional");
            try strat(vid).earn(_earnFees) returns (bool success, uint256 wantLockedTotal) {
                if (success) {
                    console.log("VHE - success");
                    vault.lastEarnBlock = uint32(block.number);
                    if (interval > 1) vault.minBlocksBetweenEarns = interval - 1; //Decrease number of blocks between earns by 1 if successful (settings.dust)
                } else {
                    vault.minBlocksBetweenEarns = interval * 21 / 20 + 1; //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
                    console.log("VHE - not success");

                }
                if (wantLockedTotal > vault.wantLockedLastUpdate) 
                {
                    require(wantLockedTotal < type(uint112).max, "VH: wantLockedTotal overflow");
                    emit Earned(vid, wantLockedTotal - vault.wantLockedLastUpdate);
                    vault.wantLockedLastUpdate = uint112(wantLockedTotal);
                }
            } catch {}
        }
    }

    //performs earn even if it's not been long enough
    function _doEarn(uint256 vid) internal {
        Vault.Info storage vault = _vaultInfo[vid];
        uint32 interval = vault.minBlocksBetweenEarns;   
        try strat(vid).earn(getEarnFees(vid)) returns (bool success, uint256 wantLockedTotal) {
            if (success) {
                vault.lastEarnBlock = uint32(block.number);
                if (interval > 1 && block.number > vault.lastEarnBlock + interval) {
                    vault.minBlocksBetweenEarns = interval - 1; //Decrease number of blocks between earns by 1 if successful (settings.dust)
                }
            } else if (block.number > vault.lastEarnBlock + interval) {
            vault.minBlocksBetweenEarns = uint32(interval * 21 / 20 + 1); //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
            }
            if (wantLockedTotal > vault.wantLockedLastUpdate) 
                {
                    require(wantLockedTotal < type(uint112).max, "VH: wantLockedTotal overflow");
                    emit Earned(vid, wantLockedTotal - vault.wantLockedLastUpdate);
                    vault.wantLockedLastUpdate = uint112(wantLockedTotal);
                }
        } catch {}
    }

    function addVault(address _strat) internal override(VaultHealerBase, VaultHealerPause) returns (uint vid) {
        return VaultHealerPause.addVault(_strat);
    }
}