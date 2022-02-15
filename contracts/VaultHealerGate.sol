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

    mapping(address => BitMaps.BitMap) maximizerMap;
    mapping(address => mapping(uint256 => uint256)) public maximizerEarningsOffset;
    mapping(uint256 => uint256) public totalMaximizerEarningsOffset;

    PendingDeposit[] private pendingDeposits; //LIFO stack, avoiding complications with maximizers

    function earn(uint256 vid) external nonReentrant whenNotPaused(vid) {
        _earn(vid);
    }

    function earn(uint256[] calldata vids) external nonReentrant {
        for (uint i; i < vids.length; i++) {
            uint vid = vids[i];
            if (!paused(vid)) _earn(vid);
        }
    }

    function _earn(uint256 vid) internal {
        VaultInfo storage vault = vaultInfo[vid];
        uint lastEarnBlock = vault.lastEarnBlock;
        
        if (lastEarnBlock == block.number) return; //earn only once per block ever
        uint lock = _lock;
        _lock = vid; //permit reentrant calls by this vault only
        try strat(vid).earn(vaultFeeManager.getEarnFees(vid)) returns (bool success, uint256 wantLockedTotal) {
            if (success) {                
                require(wantLockedTotal < type(uint112).max, "VH: wantLockedTotal overflow");
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
        vault.lastEarnBlock = uint32(block.number);
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
        VaultInfo storage vault = vaultInfo[_vid];

        pendingDeposits.push() = PendingDeposit({
            token: vault.want,
            amount0: uint96(_wantAmt >> 96),
            from: _from,
            amount1: uint96(_wantAmt)
        });
        
        IStrategy vaultStrat = strat(_vid);

        // we call an earn on the vault before we action the _deposit
        if (vault.noAutoEarn & 1 == 0) _earn(_vid); 

        // we make the deposit
        (uint256 wantAdded, uint256 vidSharesAdded) = vaultStrat.deposit(_wantAmt, totalSupply(_vid));

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

    function _withdraw(uint256 _vid, uint256 _wantAmt, address _from, address _to) private reentrantOnlyByStrategy(_vid) {
        VaultInfo storage vault = vaultInfo[_vid];
        require(balanceOf(_from, _vid) > 0, "User has 0 shares");
        
        if (vault.noAutoEarn & 2 == 0) _earn(_vid); 

        IStrategy vaultStrat = strat(_vid);

        (uint256 vidSharesRemoved, uint256 wantAmt) = vaultStrat.withdraw(_wantAmt, balanceOf(_from, _vid), totalSupply(_vid));

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
                vault.want.safeTransferFrom(address(vaultStrat), feeReceiver, feeAmt); //todo: zap to correct fee token
            }
        } catch {}

        //this call transfers wantTokens from the strat to the user
        vault.want.safeTransferFrom(address(vaultStrat), _to, wantAmt);

        emit Withdraw(_from, _to, _vid, wantAmt); //todo shouldn't this emit wantAmt?
    }

    // Withdraw everything from vault for yourself
    function withdrawAll(uint256 _vid) external {
        _withdraw(_vid, type(uint112).max, _msgSender(), _msgSender());
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint112 _amount) external {
        PendingDeposit storage pendingDeposit = pendingDeposits[pendingDeposits.length - 1];
        require(_amount <= uint(pendingDeposit.amount0) << 96 | uint(pendingDeposit.amount1), "VH: strategy requesting more tokens than authorized");
        pendingDeposit.token.safeTransferFrom(
            pendingDeposit.from,
            _to,
            _amount
        );
        pendingDeposits.pop();
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
            uint amount = amounts[i];
            updateOffsetsOnTransfer(vid, from, to, amount);
        }
    }

    //For a maximizer vault, this is all of the reward tokens earned, paid out, or offset. Used in calculations 
    function virtualTargetBalance(uint vid) internal view returns (uint256) {
        return balanceOf(address(strat(vid)), vid >> 16) + totalMaximizerEarningsOffset[vid];
    }
    //Returns the number of target shares a user is entitled to, for one maximizer
    function targetSharesFromMaximizer(uint _vid, address _account) internal view returns (uint256) {
        uint _totalSupply = totalSupply(_vid);
        if (_totalSupply == 0) return 0; //would divide by zero, and there would be no rewards
        uint amount = virtualTargetBalance(_vid) * balanceOf(_account, _vid) / _totalSupply;
        uint accountOffset = maximizerEarningsOffset[_account][_vid];
        return amount > accountOffset ? amount - accountOffset : 0;
    }

    //Overrides the balanceOf ERC1155 function to show the true balance an account owns and is able to spend
    function balanceOf(address _account, uint _vid) public view override returns (uint amount) {
        return super.balanceOf(_account, _vid) + totalForAllMaximizersOfTargetAndAccount(_vid, _account, targetSharesFromMaximizer);
    }

    function rawBalanceOf(address _account, uint _vid) public view returns (uint amount) {
        return super.balanceOf(_account, _vid);
    }

    // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    // Also sets and unsets the maximizerMap
    function updateOffsetsOnTransfer(uint _vid, address _from, address _to, uint _vidSharesTransferred) internal {
        if (_vid < 2**16) return; //not a maximizer, so nothing to do

        //calculate the offset amount
        uint _totalSupply = totalSupply(_vid);
        if (_totalSupply == 0) return; //would divide by zero and there's nothing here
        uint numerator = _vidSharesTransferred * virtualTargetBalance(_vid);
        uint shareOffset = numerator / _totalSupply;

        //For deposit/mint, ceildiv logic is used in order to prevent rounding exploits and subtraction underflow
        if (_from == address(0)) {
            maximizerMap[_to].set(_vid);
            shareOffset += numerator % _totalSupply == 0 ? 0 : 1;
            maximizerEarningsOffset[_to][_vid] += shareOffset;
            totalMaximizerEarningsOffset[_vid] += shareOffset;
        } else if (_to == address(0)) { //withdrawal/burn
        //Must give the sender all their tokens so they may spend them
            realizeTargetShares(_vid, _from);
            doForAllMaximizersOfTargetAndAccount(_vid, _from, realizeTargetShares);
            maximizerEarningsOffset[_from][_vid] -= shareOffset;
            totalMaximizerEarningsOffset[_vid] -= shareOffset;
            if (_vidSharesTransferred == balanceOf(_from, _vid)) maximizerMap[_from].unset(_vid);
        } else { //transfer
            
            realizeTargetShares(_vid, _from);
            doForAllMaximizersOfTargetAndAccount(_vid, _from, realizeTargetShares);
            maximizerEarningsOffset[_from][_vid] -= shareOffset;
            maximizerEarningsOffset[_to][_vid] += shareOffset;
            if (_vidSharesTransferred > 0) {
                maximizerMap[_to].set(_vid);
                if (_vidSharesTransferred == balanceOf(_from, _vid))
                    maximizerMap[_from].unset(_vid);
            }
        }
    }
    //For some maximizer, transfers target ERC1155 shares to the user and offsets them
    function realizeTargetShares(uint _vid, address _account) internal returns (uint amount) {
        amount = targetSharesFromMaximizer(_vid, _account);
        if (amount > 0) {
            _safeTransferFrom(address(strat(_vid)), _account, _vid >> 16, amount, hex''); //target shares from maximizer to user
            maximizerEarningsOffset[_account][_vid] += amount;
            totalMaximizerEarningsOffset[_vid] += amount;
        }
    }

    //Finds all maximizers of some target vault where the user account has a nonzero balance
    function totalForAllMaximizersOfTargetAndAccount(uint _targetVid, address _account, function(uint,address) view returns (uint) f) internal view returns (uint total){
        uint numMaximizers = vaultInfo[_targetVid].numMaximizers;

        for (
            uint b = _targetVid << 8; // left 16 for target to maximizer, right 8 for 256-bit map
            b < (_targetVid << 8) + (numMaximizers >> 8);
            b++
        ) {
            uint map = maximizerMap[_account]._data[b]; //bitmap of up to 256 maximizers where the user has deposits
            for (uint vid = b << 8; map > 0;) { //terminate on empty bitmap
                if (map & 0xff == 0) { //jump 8 bits at a time if all are empty
                    map >>= 8;
                    vid += 8;
                    continue;
                }
                if (map & 1 == 1) { //user has shares, so look for them and add them
                    total += f(vid, _account);
                }
                map >>= 1;
                vid += 1;
            }
        }
    }

    //This should be identical to the previous function except for the view modifiers
    function doForAllMaximizersOfTargetAndAccount(uint _targetVid, address _account, function(uint,address) returns (uint) f) internal returns (uint total){
            uint numMaximizers = vaultInfo[_targetVid].numMaximizers;

            for (
                uint b = _targetVid << 8; // left 16 for target to maximizer, right 8 for 256-bit map
                b < (_targetVid << 8) + (numMaximizers >> 8);
                b++
            ) {
                uint map = maximizerMap[_account]._data[b]; //bitmap of up to 256 maximizers where the user has deposits
                for (uint vid = b << 8; map > 0;) { //terminate on empty bitmap
                    if (map & 0xff == 0) { //jump 8 bits at a time if all are empty
                        map >>= 8;
                        vid += 8;
                        continue;
                    }
                    if (map & 1 == 1) { //user has shares, so look for them and add them
                        total += f(vid, _account);
                    }
                    map >>= 1;
                    vid += 1;
                }
            }
        }
}
