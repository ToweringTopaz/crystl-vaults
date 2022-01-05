// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerPause.sol";
import "./VaultHealerFees.sol";

//For calling the earn function
abstract contract VaultHealerEarn is VaultHealerPause, VaultHealerFees {

    function earnAll() external nonReentrant {

        VaultFee[] memory _defaultEarnFees = defaultEarnFees;
        uint bucketLength = (_vaultInfo.length >> 8) + 1; // use one uint256 per 256 vaults

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i]; //earn unpaused vaults
            uint feeMap = _overrideDefaultEarnFees._data[i];
            uint end = (i+1) << 8; // buckets end at multiples of 256
            if (_vaultInfo.length < end) end = _vaultInfo.length; //or if less, the final pool
            for (uint j = i << 8; j < end; j++) {
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    _tryEarn(j, feeMap & 1 > 0 ? _vaultInfo[i].earnFees : _defaultEarnFees, false);
                }
                earnMap >>= 1; //shift away the used bit
                feeMap >>= 1;

                if (earnMap == 0) break;
            }
        }
    }
    
    function earnSome(uint256[] calldata vids) external nonReentrant {

        VaultFee[] memory _defaultEarnFees = defaultEarnFees;
        uint bucketLength = (_vaultInfo.length >> 8) + 1; // use one uint256 per 256 vaults
        uint256[] memory selBuckets = new uint256[](bucketLength); //BitMap of selected vids

        for (uint i; i < vids.length; i++) { //memory bitmap of all selected vids
            uint vid = vids[i];
            if (vid <= _vaultInfo.length)
                selBuckets[vid >> 8] |= 1 << (vid & 0xff); //set bit for selected vid
        }

        for (uint i; i < bucketLength; i++) {
            uint earnMap = pauseMap._data[i] & selBuckets[i]; //earn selected, unpaused vaults
            console.log("earnMap: ", earnMap);
            uint feeMap = _overrideDefaultEarnFees._data[i];

            uint end = (i+1) << 8; // buckets end at multiples of 256
            for (uint j = i << 8; j < end; j++) {//0-255, 256-511, ...
                if (earnMap & 1 > 0) { //smallest bit is "true"
                    _tryEarn(j, feeMap & 1 > 0 ? _vaultInfo[i].earnFees : _defaultEarnFees, false);
                }
                earnMap >>= 1; //shift away the used bit
                feeMap >>= 1;

                if (earnMap == 0) break; //if bucket is empty, done with bucket
            }
        }
    }
    function earn(uint256 vid) external whenNotPaused(vid) nonReentrant {
        _tryEarn(vid, getEarnFees(vid), true);
    }

    function _earnBeforeTx(uint256 vid) internal {
        _tryEarn(vid, getEarnFees(vid), true);
    }

    function _tryEarn(uint256 vid, VaultFee[] memory _earnFees, bool forced) private {
        VaultInfo storage vault = _vaultInfo[vid];
        uint16 interval = vault.settings.minBlocksBetweenEarns;
        uint nativeBalanceBefore = address(this).balance;

        if (forced || block.number > vault.lastEarnBlock + interval) {
            try vault.strat.earn(vault.settings) returns (bool success, uint wantLocked) {
                if (success) {
                    assert(wantLocked > 0);
                    vault.lastEarnBlock = uint48(block.number);
                    if (interval > 1) vault.settings.minBlocksBetweenEarns = interval - 1; //Decrease number of blocks between earns by 1 if successful (settings.dust)

                    uint earnedAmt = distributeFees(_earnFees, address(this).balance - nativeBalanceBefore); //Pay fees and get amount earned after fees
                    
                    uint exportAmt = vault.exportSharesTotal * earnedAmt / wantLocked; //Portion to be exported rather than autocompounded
                    uint compoundAmt = earnedAmt - exportAmt; //Portion to be autocompounded
                    uint depositAmt = vault.pendingImportTotal; // Imports to be deposited;
                    uint sharesAdded = vault.strat.compound{value: compoundAmt + depositAmt}(depositAmt, vault.exportSharesTotal, totalSupply(vid));

                    //todo: distribute added shares


                } else {
                    vault.settings.minBlocksBetweenEarns = interval * 21 / 20 + 1; //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
                }
            } catch {}
        }
    }

    function addVault(address _strat, VaultSettings calldata _settings) public override(VaultHealerBase, VaultHealerPause) returns (uint vid) {
        return VaultHealerPause.addVault(_strat, _settings);
    }

    receive() payable external {
        require(Address.isContract(msg.sender), "VH: receive function is for contracts only"); //generally used by a router
    }
}