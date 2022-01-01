// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerPause.sol";
import "./VaultHealerFees.sol";

//For calling the earn function
abstract contract VaultHealerEarn is VaultHealerPause, VaultHealerFees {

    uint256 constant public WNATIVE_1155 = 0;

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
                    _tryEarn(j, feeMap & 1 > 0 ? _vaultInfo[i].earnFees : _defaultEarnFees, false);
                }
                earnMap >>= 1; //shift away the used bit
                feeMap >>= 1;

                if (earnMap == 0) break;
            }
        }
    }
    
    function earnSome(uint256[] calldata vids) external nonReentrant {

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

    function _tryEarn(uint256 vid, VaultFees memory _earnFees, bool forced) private {
        VaultInfo storage vault = _vaultInfo[vid];
        uint interval = vault.minBlocksBetweenEarns;
        uint nativeBalanceBefore = address(this).balance;

        if (forced || block.number > vault.lastEarnBlock + interval) {
            try vault.strat.earn(_earnFees) returns (bool success) {
                if (success) {
                    vault.lastEarnBlock = block.number;
                    if (interval > 1) vault.minBlocksBetweenEarns = interval - 1; //Decrease number of blocks between earns by 1 if successful (settings.dust)

                    uint earnedAmt = address(this).balance - nativeBalanceBefore;

                    //Collect fees by minting erc1155 wnative tokens to the fee receivers, reducing earnedAmt accordingly
                    uint feeAmt = _earnFees.userReward.rate * earnedAmt;
                    _mint(tx.origin, WNATIVE_1155, feeAmt, hex'');
                    uint _earnedAmt = earnedAmt - feeAmt;
                    feeAmt = _earnFees.treasuryFee.rate * earnedAmt;
                    _mint(_earnFees.treasuryFee.receiver, WNATIVE_1155, feeAmt, hex'');
                    _earnedAmt -= feeAmt;
                    feeAmt = _earnFees.burn.rate * earnedAmt;
                    _mint(_earnFees.burn.receiver, WNATIVE_1155, feeAmt, hex'');
                    earnedAmt = _earnedAmt - feeAmt;
                    
                    uint exportAmt = vault.exportSharesTotal * earnedAmt / vault.strat.wantLockedTotal(); //Portion to be exported rather than autocompounded
                    uint compoundAmt = earnedAmt - exportAmt; //Portion to be autocompounded
                    uint depositAmt = vault.pendingImportTotal; // Imports to be deposited;
                    uint amountIn = compoundAmt + depositAmt;
                    uint sharesAdded = vault.strat.compound{value: amountIn}(depositAmt, vault.exportSharesTotal, totalSupply(vid));

                    //todo: distribute added shares


                } else {
                    vault.minBlocksBetweenEarns = interval * 21 / 20 + 1; //Increase number of blocks between earns by 5% + 1 if unsuccessful (settings.dust)
                }
            } catch {}
        }
    }

    function addVault(address _strat, uint minBlocksBetweenEarns) public override(VaultHealerBase, VaultHealerPause) returns (uint vid) {
        return VaultHealerPause.addVault(_strat, minBlocksBetweenEarns);
    }

    receive() payable external {

    }
}