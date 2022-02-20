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
    mapping(address => mapping(uint256 => uint256)) public maximizerEarningsOffset;
    mapping(uint256 => uint256) public totalMaximizerEarningsOffset;
    mapping(uint256 => uint256) public totalSupply;

    mapping(address => PendingDeposit) private pendingDeposits;

    function earn(uint256 vid) external nonReentrant whenNotPaused(vid) {
        if (vaultInfo[vid].lastEarnBlock != block.number) _earn(vid, vaultFeeManager.getEarnFees(vid));
    }

    function earn(uint256[] calldata vids) external nonReentrant {
        Fee.Data[3][] memory fees = vaultFeeManager.getEarnFees(vids);
        for (uint i; i < vids.length; i++) {
            uint vid = vids[i];
            VaultInfo storage vault = vaultInfo[vid];
            bool active = vault.active;
            uint lastEarnBlock = vault.lastEarnBlock;
            if (active && lastEarnBlock != block.number) _earn(vid, fees[i]);
        }
    }

    function _earn(uint256 vid) internal {
        _earn(vid, vaultFeeManager.getEarnFees(vid));
    }

    function _earn(uint256 vid, Fee.Data[3] memory fees) internal {
        try strat(vid).earn(fees) returns (bool success, uint256 wantLockedTotal) {
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
    }
    
    //Allows maximizers to make reentrant calls, only to deposit to their target. Also updates totalMaximizerEarningsOffset
    function maximizerDeposit(uint vid, uint _wantAmt) external whenNotPaused(vid) {
        require(address(strat(vid)) == _msgSender(), "VH: sender does not match vid");
        uint targetVid = vid >> 16;
        uint targetBalance = balanceOf(_msgSender(), targetVid); //
        _deposit(targetVid, _wantAmt, _msgSender(), _msgSender());
        totalMaximizerEarningsOffset[vid] += balanceOf(_msgSender(), targetVid) - targetBalance;
    }

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 vid, uint256 _wantAmt) external whenNotPaused(vid) nonReentrant {
        _deposit(vid, _wantAmt, _msgSender(), _msgSender());
    }

    // For depositing for other users
    function deposit(uint256 vid, uint256 _wantAmt, address to) external whenNotPaused(vid) nonReentrant {
        _deposit(vid, _wantAmt, _msgSender(), to);
    }

    function _deposit(uint256 vid, uint256 _wantAmt, address from, address to) private {
        VaultInfo memory vault = vaultInfo[vid];
        console.log("_wantAmt as _deposit starts ", _wantAmt);
        // If enabled, we call an earn on the vault before we action the _deposit
        if (vault.noAutoEarn & 1 == 0 && vault.active && vault.lastEarnBlock != block.number) _earn(vid); 

        pendingDeposits[address(strat(vid))] = PendingDeposit({
            token: vault.want,
            amount0: uint96(_wantAmt >> 96),
            from: from,
            amount1: uint96(_wantAmt)
        });
    
        IStrategy vaultStrat = strat(vid);
        // we make the deposit
        (uint256 wantAdded, uint256 vidSharesAdded) = vaultStrat.deposit(_wantAmt, totalSupply[vid]);
        console.log("wantAdded: ", wantAdded);
        console.log("vidSharesAdded: ", vidSharesAdded);

        //we mint tokens for the user via the 1155 contract
        _mint(
            to,
            vid, //use the vid of the strategy 
            vidSharesAdded,
            hex'' //leave this blank for now
        );

        emit Deposit(from, to, vid, wantAdded);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 vid, uint256 _wantAmt) external nonReentrant {
        _withdraw(vid, _wantAmt, _msgSender(), _msgSender());
    }

    // For withdrawing to other address
    function withdraw(uint256 vid, uint256 _wantAmt, address to) external nonReentrant {
        _withdraw(vid, _wantAmt, _msgSender(), to);
    }

    function withdrawFrom(uint256 vid, uint256 _wantAmt, address from, address to) external nonReentrant {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        _withdraw(vid, _wantAmt, from, to);
    }

    function _withdraw(uint256 vid, uint256 _wantAmt, address from, address to) private {
		uint fromBalance = balanceOf(from, vid);
        require(fromBalance > 0, "User has 0 shares");
        
        VaultInfo memory vault = vaultInfo[vid];

        // we call an earn on the vault before we action the _deposit
        if (vault.noAutoEarn & 2 == 0 && vault.lastEarnBlock != block.number) _earn(vid); 

        IStrategy vaultStrat = strat(vid);

        (uint256 vidSharesRemoved, uint256 wantAmt) = vaultStrat.withdraw(_wantAmt, fromBalance, totalSupply[vid]);

        //burn the tokens equal to vidSharesRemoved
        _burn(
            from,
            vid,
            vidSharesRemoved
        );
        
        //withdraw fee is implemented here
        try vaultFeeManager.getWithdrawFee(vid) returns (address feeReceiver, uint16 feeRate) {
            //hardcoded 3% max fee rate
            if (feeReceiver != address(0) && feeRate <= 300 && !paused(vid)) { //waive withdrawal fee on paused vaults as there's generally something wrong
                uint feeAmt = wantAmt * feeRate / 10000;
                wantAmt -= feeAmt;
                vault.want.safeTransferFrom(vaultStrat, feeReceiver, feeAmt);
            }
        } catch Error(string memory reason) {
            emit FailedWithdrawFee(vid, reason);
        } catch (bytes memory reason) {
            emit FailedWithdrawFeeBytes(vid, reason);
        }

        //this call transfers wantTokens from the strat to the user
        vault.want.safeTransferFrom(vaultStrat, to, wantAmt);

        emit Withdraw(from, to, vid, wantAmt);
    }

    // Withdraw everything from vault for yourself
    function withdrawAll(uint256 vid) external nonReentrant {
        _withdraw(vid, type(uint256).max, _msgSender(), _msgSender());
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address to, uint112 _amount) external {
        IERC20 token = pendingDeposits[msg.sender].token;
        uint amount0 = pendingDeposits[msg.sender].amount0;
        address from = pendingDeposits[msg.sender].from;
        uint amount1 = pendingDeposits[msg.sender].amount1;
        require(_amount <= amount0 << 96 | amount1, "VH: strategy requesting more tokens than authorized");
        delete pendingDeposits[msg.sender];

        token.safeTransferFrom(
            from,
            to,
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

        for (uint i; i < ids.length; i++) {

            uint vid = ids[i];
            uint targetVid = vid >> 16;
            uint totalOffset;
            uint amount = amounts[i];
            if (targetVid > 0 && (totalOffset = totalMaximizerEarningsOffset[vid]) > 0) {
                address vaultStrat = address(strat(vid));
                uint _totalSupply = totalSupply[vid];
            

                if (from != address(0)) {
                    transferTargetSharesDue(from, vid);

                    if (to == address(0)) {
                        //Update total supply and total offset at the same time to maintain the ratio
                        totalMaximizerEarningsOffset[vid] = totalOffset - amount * totalOffset / _totalSupply;
                        totalSupply[vid] -= amount;
                    }                 
                }
                if (to != address(0)) {
                    transferTargetSharesDue(to, vid);
                    if (from == address(0)) {
                        //Update total supply and total offset at the same time to maintain the ratio
                        totalMaximizerEarningsOffset[vid] = totalOffset + amount * totalOffset / _totalSupply;
                        totalSupply[vid] += amount;
                    }
                }
            } else {
                if (to == address(0)) {
                    totalSupply[vid] -= amount;
                } else if (from == address(0)) {
                    totalSupply[vid] += amount;
                }
            }
        }
    }
    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._afterTokenTransfer(operator, from, to, ids, amounts, data);
        for (uint i; i < ids.length; i++) {
            uint vid = ids[i];
            if (vid >> 16 > 0) {
                //Update final offsets using final balances
                uint totalOffset = totalMaximizerEarningsOffset[vid];
                uint _totalSupply = totalSupply[vid];
                if (from != address(0)) maximizerEarningsOffset[from][vid] = balanceOf(from, vid) * totalOffset / _totalSupply;
                if (to != address(0)) maximizerEarningsOffset[to][vid] = balanceOf(to, vid) * totalOffset / _totalSupply;
            }
        
        }
    }
    function transferTargetSharesDue(address account, uint vid) private {
        //Target vault tokens owned, before offset
        uint fullShareValue = balanceOf(account, vid) * totalMaximizerEarningsOffset[vid] / totalSupply[vid]; 
        
        //Get offset and set it to max. This prevents reentrancy or batch transfer issues. The final offset is 
        //set at the end of the transfer, after balances are set.
        uint offset = maximizerEarningsOffset[account][vid];
        maximizerEarningsOffset[account][vid] = type(uint).max; 
        
        //Calculate and pay any owed target shares
        if (fullShareValue > offset) _safeTransferFrom(address(strat(vid)), account, vid >> 16, fullShareValue - offset, '');
    }
}
