// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerBase.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";

abstract contract VaultHealerGate is VaultHealerBase {
    using SafeERC20 for IERC20;
    using BitMaps for BitMaps.BitMap;

    struct PendingDeposit {
        IERC20 token;
        uint96 amount0;
        address from;
        uint96 amount1;
    }
    mapping(address => mapping(uint256 => uint256)) public maximizerEarningsOffset;
    mapping(uint256 => uint256) public totalMaximizerEarningsOffset;

    mapping(address => PendingDeposit) private pendingDeposits;

    //For front-end and general purpose external compounding. Returned amount is zero on failure, or the gas cost on success
    function earn(uint256 vid) external nonReentrant whenNotPaused(vid) returns (uint successGas) {
        if (vaultInfo[vid].lastEarnBlock == block.number) return 0;
        Fee.Data[3] memory fees = vaultFeeManager.getEarnFees(vid);

        uint gasBefore = gasleft();
        if (_earn(vid, fees)) return gasBefore - gasleft();
        else return 0;
    }

    //For front-end and general purpose external compounding. Returned amounts are zero on failure, or the gas cost on success
    function earn(uint256[] calldata vids) external nonReentrant returns (uint[] memory successGas) {
        Fee.Data[3][] memory fees = vaultFeeManager.getEarnFees(vids);
        successGas = new uint[](vids.length);
        for (uint i; i < vids.length; i++) {
            uint vid = vids[i];
            VaultInfo storage vault = vaultInfo[vid];
            if (vault.active && vault.lastEarnBlock != block.number) {
                uint gasBefore = gasleft();
                if (_earn(vid, fees[i])) successGas[i] = gasBefore - gasleft();
            }
        }
    }

    function _earn(uint256 vid) internal {
        _earn(vid, vaultFeeManager.getEarnFees(vid));
    }

    function _earn(uint256 vid, Fee.Data[3] memory fees) internal returns (bool) {
        vaultInfo[vid].lastEarnBlock = uint48(block.number);
        try strat(vid).earn(fees) returns (bool success, uint256 wantLockedTotal) {
            if (success) {                
                emit Earned(vid, wantLockedTotal);
                return true;
            }
        } catch Error(string memory reason) {
            emit FailedEarn(vid, reason);
        } catch (bytes memory reason) {
            emit FailedEarnBytes(vid, reason);
        }
        return false;
    }
    
    //Allows maximizers to make reentrant calls, only to deposit to their target
    function maximizerDeposit(uint _vid, uint _wantAmt) external payable whenNotPaused(_vid) {
        address sender = _msgSender();
        require(address(strat(_vid)) == sender, "VH: sender does not match vid");
        //totalMaximizerEarningsOffset[_vid] += 
        _deposit(_vid >> 16, _wantAmt, sender, sender);
    }

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _vid, uint256 _wantAmt) external payable whenNotPaused(_vid) nonReentrant {
        _deposit(_vid, _wantAmt, _msgSender(), _msgSender());
    }

    // For depositing for other users
    function deposit(uint256 _vid, uint256 _wantAmt, address _to) external payable whenNotPaused(_vid) nonReentrant {
        _deposit(_vid, _wantAmt, _msgSender(), _to);
    }

    function _deposit(uint256 _vid, uint256 _wantAmt, address _from, address _to) private returns (uint256 vidSharesAdded) {
        VaultInfo memory vault = vaultInfo[_vid];
        // If enabled, we call an earn on the vault before we action the _deposit
        if (vault.noAutoEarn & 1 == 0 && vault.active && vault.lastEarnBlock != block.number) _earn(_vid); 

        IStrategy vaultStrat = strat(_vid);

        if (_wantAmt > 0) pendingDeposits[address(vaultStrat)] = PendingDeposit({
            token: vault.want,
            amount0: uint96(_wantAmt >> 96),
            from: _from,
            amount1: uint96(_wantAmt)
        });
        
        uint256 totalSupplyBefore = totalSupply(_vid);

        // we make the deposit
        uint256 wantAdded;
        (wantAdded, vidSharesAdded) = vaultStrat.deposit{value: msg.value}(_wantAmt, totalSupplyBefore);

        // if this is a maximizer vault, do these extra steps
        if (_vid > 2**16 && totalSupplyBefore > 0)
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
    function withdraw(uint256 _vid, uint256 _wantAmt) external nonReentrant {
        _withdraw(_vid, _wantAmt, _msgSender(), _msgSender());
    }

    // For withdrawing to other address
    function withdraw(uint256 _vid, uint256 _wantAmt, address _to) external nonReentrant {
        _withdraw(_vid, _wantAmt, _msgSender(), _to);
    }

    function withdrawFrom(uint256 _vid, uint256 _wantAmt, address _from, address _to) external nonReentrant {
        require(
            _from == _msgSender() || isApprovedForAll(_from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        _withdraw(_vid, _wantAmt, _from, _to);
    }

    function _withdraw(uint256 _vid, uint256 _wantAmt, address _from, address _to) private {
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
        //burn the tokens equal to vidSharesRemoved
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
        } catch Error(string memory reason) {
            emit FailedWithdrawFee(_vid, reason);
        } catch (bytes memory reason) {
            emit FailedWithdrawFeeBytes(_vid, reason);
        }

        //this call transfers wantTokens from the strat to the user
        vault.want.safeTransferFrom(address(vaultStrat), _to, wantAmt);

        emit Withdraw(_from, _to, _vid, wantAmt);
    }

    // Withdraw everything from vault for yourself
    function withdrawAll(uint256 _vid) external nonReentrant {
        _withdraw(_vid, type(uint256).max, _msgSender(), _msgSender());
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint112 _amount) external {
        IERC20 token = pendingDeposits[msg.sender].token;
        console.log("xpd: ", address(token));
        uint amount0 = pendingDeposits[msg.sender].amount0;
        address from = pendingDeposits[msg.sender].from;
        console.log("from: ", from);
        uint amount1 = pendingDeposits[msg.sender].amount1;
        console.log("amount: ", amount0 << 96 | amount1);
        console.log("balance: ", token.balanceOf(from));
        require(_amount <= amount0 << 96 | amount1, "VH: strategy requesting more tokens than authorized");
        delete pendingDeposits[msg.sender];

        token.safeTransferFrom(
            from,
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
            if (from != address(0) && to != address(0)) {
                for (uint i; i < ids.length; i++) {
                    uint vid = ids[i];

                    if (vid > 2**16) {
                        _earn(vid);
                        uint amount = amounts[i];
                        withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(vid, from, amount);
                        UpdateOffsetsOnDeposit(vid, to, amount); 
                    }

                }
            }
        }

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function UpdateOffsetsOnDeposit(uint256 _vid, address _from, uint256 _vidSharesAdded) internal {
        uint256 targetVid = _vid >> 16;

        //calculate the offset for this particular deposit
        uint256 targetVidSharesOwnedByMaxiBefore = balanceOf(address(strat(_vid)), targetVid) + totalMaximizerEarningsOffset[_vid]; //balanceOf is looking at shares (1155) owned by the strat at _vid
        uint112 targetVidTokenOffset = uint112(_vidSharesAdded * targetVidSharesOwnedByMaxiBefore / totalSupply(_vid)); //but this is a token offset, not a shares offset?

        // increment the offsets for user and for vid
        maximizerEarningsOffset[_from][_vid] += targetVidTokenOffset;
        totalMaximizerEarningsOffset[_vid] += targetVidTokenOffset; 

    }

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(uint256 _vid, address _from, uint256 _vidSharesRemoved) internal {
        uint targetVid = _vid >> 16;
        VaultInfo storage target = vaultInfo[targetVid];

        uint targetTotalSupply = totalSupply(targetVid);
        if (targetTotalSupply == 0) return;

        uint fromOffset = maximizerEarningsOffset[_from][_vid];
        uint totalOffset = totalMaximizerEarningsOffset[_vid];

        address vaultStrat = address(strat(_vid));

        // calculate the amount of targetVid token to be withdrawn
        uint256 targetVidShares = _vidSharesRemoved * (balanceOf(vaultStrat, targetVid) + totalOffset) / totalSupply(_vid) 
            - fromOffset * _vidSharesRemoved / balanceOf(_from, _vid);

        uint256 targetVidAmount = targetVidShares * strat(targetVid).wantLockedTotal() / targetTotalSupply;
        if (targetVidAmount == 0) return;

        // withdraw an amount of reward token from the target vault proportional to the users withdrawal from the main vault
        _withdraw(targetVid, targetVidAmount, vaultStrat, _from);
        target.want.safeTransferFrom(vaultStrat, _from, target.want.balanceOf(vaultStrat));
        
        uint removedPortionOfOffset = fromOffset * _vidSharesRemoved / balanceOf(_from, _vid);

        // update the offsets for user and for vid
        totalMaximizerEarningsOffset[_vid] -= removedPortionOfOffset;
        maximizerEarningsOffset[_from][_vid] -= removedPortionOfOffset;

        emit MaximizerWithdraw(_from, _vid, targetVidShares);
    }
}
