// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerBase.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "hardhat/console.sol";

abstract contract VaultHealerGate is VaultHealerBase {
    using SafeERC20 for IERC20;
    using BitMaps for BitMaps.BitMap;

    struct PendingDeposit {
        IERC20 token;
        uint96 amount0;
        address from;
        uint96 amount1;
    }
    mapping(address => mapping(uint256 => uint112)) public maximizerEarningsOffset;
    mapping(uint256 => uint112) public totalMaximizerEarningsOffset;

    mapping(address => PendingDeposit) private pendingDeposits;

    function earn(uint256 vid) external nonReentrant whenNotPaused(vid) {
        VaultInfo storage vault = vaultInfo[vid];
        bool active = vault.active;
        uint48 lastEarnBlock = vault.lastEarnBlock;
        if (active && lastEarnBlock != block.number) _earn(vid);
    }

    function earn(uint256[] calldata vids) external nonReentrant {
        for (uint i; i < vids.length; i++) {
            uint vid = vids[i];
            VaultInfo storage vault = vaultInfo[vid];
            bool active = vault.active;
            uint48 lastEarnBlock = vault.lastEarnBlock;
            if (active && lastEarnBlock != block.number) _earn(vid);
        }
    }

    function _earn(uint256 vid) internal {
        uint lock = _lock;
        _lock = vid; //permit reentrant calls by this vault only
        try strat(vid).earn(vaultFeeManager.getEarnFees(vid)) returns (bool success, uint256 wantLockedTotal) {
            if (success) {                
                emit Earned(vid, wantLockedTotal);
            }
        } catch Error(string memory reason) {
            emit FailedEarn(vid, reason);
            console.log("earn failed");
            console.log(vid, reason);
        } catch (bytes memory reason) {
            emit FailedEarnBytes(vid, reason);
            console.log("earn failed");
            console.log(vid, string(reason));
        }
        _lock = lock; //reset reentrancy state
    }

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _vid, uint256 _wantAmt) external whenNotPaused(_vid) {
        _deposit(_vid, _wantAmt, _msgSender(), _msgSender());
    }

    // For depositing for other users
    function deposit(uint256 _vid, uint256 _wantAmt, address _to) external whenNotPaused(_vid) {
        _deposit(_vid, _wantAmt, _msgSender(), _to);
    }

    function _deposit(uint256 _vid, uint256 _wantAmt, address _from, address _to) private reentrantOnlyByStrategy(_vid) {
        VaultInfo memory vault = vaultInfo[_vid];

        // If enabled, we call an earn on the vault before we action the _deposit
        if (vault.noAutoEarn & 1 == 0 && vault.active && vault.lastEarnBlock != block.number) _earn(_vid); 

        pendingDeposits[address(strat(_vid))] = PendingDeposit({
            token: vault.want,
            amount0: uint96(_wantAmt >> 96),
            from: _from,
            amount1: uint96(_wantAmt)
        });
        
        IStrategy vaultStrat = strat(_vid);
        uint256 wantLockedBefore = vaultStrat.wantLockedTotal();

        // we make the deposit
        (uint256 wantAdded, uint256 vidSharesAdded) = vaultStrat.deposit(_wantAmt, totalSupply(_vid));
        console.log(_vid);
        console.log(totalSupply(_vid));
        // if this is a maximizer vault, do these extra steps
        if (_vid > 2**16 && wantLockedBefore > 0)
            UpdateOffsetsOnDeposit(_vid, _to, vidSharesAdded);

        //we mint tokens for the user via the 1155 contract
        _mint(
            _to,
            _vid, //use the vid of the strategy 
            vidSharesAdded,
            hex'' //leave this blank for now
        );

        emit Deposit(_from, _to, _vid, wantAdded);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _vid, uint256 _wantAmt) external {
        _withdraw(_vid, _wantAmt, _msgSender(), _msgSender());
    }

    // For withdrawing to other address
    function withdraw(uint256 _vid, uint256 _wantAmt, address _to) external {
        _withdraw(_vid, _wantAmt, _msgSender(), _to);
    }

    function withdrawFrom(uint256 _vid, uint256 _wantAmt, address _from, address _to) external {
        require(
            _from == _msgSender() || isApprovedForAll(_from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        _withdraw(_vid, _wantAmt, _from, _to);
    }

    function _withdraw(uint256 _vid, uint256 _wantAmt, address _from, address _to) private  { //reentrantOnlyByStrategy(_vid)
		uint fromBalance = balanceOf(_from, _vid);
        require(fromBalance > 0, "User has 0 shares");
        
        VaultInfo memory vault = vaultInfo[_vid];

        // we call an earn on the vault before we action the _deposit
        if (vault.noAutoEarn & 2 == 0 && vault.lastEarnBlock != block.number) _earn(_vid); 

        IStrategy vaultStrat = strat(_vid);

        (uint256 vidSharesRemoved, uint256 wantAmt) = vaultStrat.withdraw(_wantAmt, fromBalance, totalSupply(_vid));

        if (_vid > 2**16) {
            withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(_vid, _from, vidSharesRemoved);
        }

        //burn the tokens equal to vidSharesRemoved todo should this be here, or higher up?
        _burn(
            _from,
            _vid,
            vidSharesRemoved
        );
        
        //withdraw fee is implemented here
        try vaultFeeManager.getWithdrawFee(_vid) returns (address feeReceiver, uint16 feeRate) {
            //hardcoded 3% max fee rate
            if (feeReceiver != address(0) && feeRate <= 300 && !paused(_vid)) { //waive withdrawal fee on paused vaults as there's generally something wrong
                uint feeAmt = wantAmt * feeRate / 10000;
                wantAmt -= feeAmt;
                vault.want.safeTransferFrom(address(vaultStrat), feeReceiver, feeAmt);
            }
        } catch {}

        //this call transfers wantTokens from the strat to the user
        vault.want.safeTransferFrom(address(vaultStrat), _to, wantAmt);

        emit Withdraw(_from, _to, _vid, wantAmt);
    }

    // Withdraw everything from vault for yourself
    function withdrawAll(uint256 _vid) external {
        _withdraw(_vid, type(uint256).max, _msgSender(), _msgSender());
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint112 _amount) external {
        PendingDeposit storage pendingDeposit = pendingDeposits[msg.sender];
        require(_amount <= uint(pendingDeposit.amount0) << 96 | uint(pendingDeposit.amount1), "VH: strategy requesting more tokens than authorized");
        pendingDeposit.token.safeTransferFrom(
            pendingDeposit.from,
            _to,
            _amount
        );
    }

    function _beforeTokenTransfer(
            address operator,
            address from,
            address to,
            uint256[] memory ids,
            uint256[] memory amounts,
            bytes memory data
        ) internal virtual override {
            super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
            console.log("made it here");
            console.log(from);
            console.log(to);
            if (from != address(0) && to != address(0)) {
                console.log("made it here2");
                for (uint i; i < ids.length; i++) {
                    console.log("made it here3");
                    uint vid = ids[i];

                    if (vid > 2**16) {
                        _earn(vid);
                        uint128 underlyingValue = uint128(amounts[i] * strat(vid).wantLockedTotal() / totalSupply(vid));
                        withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(vid, from, underlyingValue);
                        console.log("got here just before updateOffsets");
                        UpdateOffsetsOnDeposit(vid, to, underlyingValue); 
                    }

                }
            }
        }

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function UpdateOffsetsOnDeposit(uint256 _vid, address _from, uint256 _vidSharesAdded) internal {
        console.log("inside update");
        IStrategy vaultStrat = strat(_vid);
        uint256 targetVid = _vid >> 16;

        //calculate the offset for this particular deposit
        uint256 targetVidSharesOwnedByMaxiBefore = balanceOf(address(vaultStrat), targetVid) + totalMaximizerEarningsOffset[_vid];
        uint112 targetVidTokenOffset = uint112(_vidSharesAdded * targetVidSharesOwnedByMaxiBefore / totalSupply(_vid)); 

        // increment the offsets for user and for vid
        maximizerEarningsOffset[_from][_vid] += targetVidTokenOffset;
        totalMaximizerEarningsOffset[_vid] += targetVidTokenOffset; 
        console.log("done update");

    }

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(uint256 _vid, address _from, uint256 _vidSharesRemoved) internal {
        console.log("inside withdraw update");
        uint targetVid = _vid >> 16;
        VaultInfo storage target = vaultInfo[targetVid];
        
        IStrategy vaultStrat = strat(_vid);
        IStrategy targetStrat = strat(targetVid);

        // calculate the amount of targetVid token to be withdrawn
        uint256 targetVidAmount = _vidSharesRemoved
            * (targetStrat.wantLockedTotal() + totalMaximizerEarningsOffset[_vid])
            / totalSupply(_vid) 
            - maximizerEarningsOffset[_from][_vid] * _vidSharesRemoved / balanceOf(_from, _vid);
        
        // withdraw proportional amount of target vault token from targetVault()
        if (targetVidAmount > 0) {
            console.log("inside targetVid conditional");

            // withdraw an amount of reward token from the target vault proportional to the users withdrawal from the main vault
            _withdraw(targetVid, targetVidAmount, address(vaultStrat), _from);
            target.want.safeTransferFrom(address(vaultStrat), _from, target.want.balanceOf(address(vaultStrat)));
                        
            // update the offsets for user and for vid
            totalMaximizerEarningsOffset[_vid] -= uint112(maximizerEarningsOffset[_from][_vid] * _vidSharesRemoved / balanceOf(_from, _vid)); 
            maximizerEarningsOffset[_from][_vid] -= uint112(maximizerEarningsOffset[_from][_vid] * _vidSharesRemoved / balanceOf(_from, _vid)); 
            }
        }
}
