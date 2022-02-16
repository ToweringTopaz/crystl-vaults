// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerBase.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract VaultHealerGate is VaultHealerBase {
    using SafeERC20 for IERC20;
    using BitMaps for BitMaps.BitMap;
    using Math for uint256;

    struct PendingDeposit {
        IERC20 token;
        uint96 amount0;
        address from;
        uint96 amount1;
    }

    mapping(address => BitMaps.BitMap) maximizerMap;
    mapping(address => mapping(uint256 => uint256)) public maximizerEarningsOffset;
    mapping(uint256 => uint256) public totalMaximizerEarningsOffset;

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
        VaultInfo storage vault = vaultInfo[_vid];
        IERC20 want = vault.want;
        uint8 noAutoEarn = vault.noAutoEarn;
        bool active = vault.active;
        uint48 lastEarnBlock = vault.lastEarnBlock;

        // If enabled, we call an earn on the vault before we action the _deposit
        if (noAutoEarn & 1 == 0 && active && lastEarnBlock != block.number) _earn(_vid); 

        IStrategy vaultStrat = strat(_vid);

        pendingDeposits[vaultStrat]= PendingDeposit({
            token: want,
            amount0: uint96(_wantAmt >> 96),
            from: _from,
            amount1: uint96(_wantAmt)
        });

        
        // we make the deposit
        (uint256 wantAdded, uint256 wantLockedBefore) = vaultStrat.deposit(_wantAmt);
        
        //calculate shares
        uint sharesAdded;
        if (_vid < 2**16 && totalSupply(_vid) > 0) { //standard case
            sharesAdded = Math.ceilDiv(wantAdded * totalSupply(_vid), wantLockedBefore);
        } else { //maximizers and empty vaults are simply 1:1 shares:tokens
            sharesAdded = wantAdded;
        }

        //we mint tokens for the user via the 1155 contract
        _mint(
            _to,
            _vid, //use the vid of the strategy 
            sharesAdded,
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
        uint balance = balanceOf(_from, _vid);
        require(balance > 0, "User has 0 shares");
        
        VaultInfo storage vault = vaultInfo[_vid];
        IERC20 want = vault.want;
        uint8 noAutoEarn = vault.noAutoEarn;
        bool active = vault.active;
        uint48 lastEarnBlock = vault.lastEarnBlock;

        // we call an earn on the vault before we action the _deposit
        if (noAutoEarn & 2 == 0 && active && lastEarnBlock != block.number) _earn(_vid); 

        IStrategy vaultStrat = strat(_vid);

        uint wantBalance = _vid < 2**16 ? balance * vaultStrat.wantLockedTotal() / totalSupply(_vid) : balance;
        uint256 wantAmt = vaultStrat.withdraw(_wantAmt, wantBalance);
        uint sharesRemoved = wantAmt;
        if (_vid < 2**16) {
            sharesRemoved = sharesRemoved * vaultStrat.wantLockedTotal() / totalSupply(_vid);
        }

        //Must happen after call to strategy in order to determine final withdraw amount
        _burn(
            _from,
            _vid,
            sharesRemoved
        );
        
        //withdraw fee is implemented here
        try vaultFeeManager.getWithdrawFee(_vid) returns (address feeReceiver, uint16 feeRate) {
            //hardcoded 3% max fee rate
            if (feeReceiver != address(0) && feeRate <= 300 && !paused(_vid)) { //waive withdrawal fee on paused vaults as there's generally something wrong
                uint feeAmt = wantAmt * feeRate / 10000;
                wantAmt -= feeAmt;
                want.safeTransferFrom(address(vaultStrat), feeReceiver, feeAmt); 
            }
        } catch {}

        //this call transfers wantTokens from the strat to the user
        want.safeTransferFrom(address(vaultStrat), _to, wantAmt);

        emit Withdraw(_from, _to, _vid, wantAmt);
    }

    // Withdraw everything from vault for yourself
    function withdrawAll(uint256 _vid) external {
        _withdraw(_vid, type(uint256).max, _msgSender(), _msgSender());
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint112 _amount) external {
        PendingDeposit storage pendingDeposit = pendingDeposits[msg.sender]; //not _msgSender as strategy contracts do not and will not use the forwarder pattern
        require(_amount <= uint(pendingDeposit.amount0) << 96 | uint(pendingDeposit.amount1), "VH: strategy requesting more tokens than authorized");
        pendingDeposit.token.safeTransferFrom(
            pendingDeposit.from,
            _to,
            _amount
        );
        delete pendingDeposits[msg.sender];
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

    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._afterTokenTransfer(operator, from, to, ids, amounts, data);

        if (to != address(0)) {
            for (uint i; i < ids.length; i++) {
                uint vid = ids[i];
                if (balanceOf(to, vid) > 0) maximizerMap[to].set(vid);
            }
        }
        if (from != address(0)) {
            for (uint i; i < ids.length; i++) {
                uint vid = ids[i];
                if (balanceOf(from, vid) == 0) maximizerMap[from].unset(vid);
            }
        }
    }


    //For a maximizer vault, this is all of the reward tokens earned, paid out, or offset. Used in calculations 
    function virtualTargetBalance(uint vid) public view returns (uint256) {
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
    function updateOffsetsOnTransfer(uint _vid, address _from, address _to, uint _vidSharesTransferred) internal {
        if (_vid < 2**16) return; //not a maximizer, so nothing to do

        //calculate the offset amount
        uint _totalSupply = totalSupply(_vid);
        uint numerator = _vidSharesTransferred * virtualTargetBalance(_vid);
        uint shareOffset = _totalSupply == 0 ? 0 : numerator / _totalSupply;

        //For deposit/mint, ceildiv logic is used in order to prevent rounding exploits and subtraction underflow
        if (_from == address(0)) {
            shareOffset += (_totalSupply == 0 || numerator % _totalSupply == 0) ? 0 : 1;
            maximizerEarningsOffset[_to][_vid] += shareOffset;
            totalMaximizerEarningsOffset[_vid] += shareOffset;
        } else if (_to == address(0)) { //withdrawal/burn
        //Must give the sender all their tokens so they may spend them
            realizeTargetShares(_vid, _from);
            doForAllMaximizersOfTargetAndAccount(_vid, _from, realizeTargetShares);
            maximizerEarningsOffset[_from][_vid] -= shareOffset;
            totalMaximizerEarningsOffset[_vid] -= shareOffset;
        } else { //transfer
            
            realizeTargetShares(_vid, _from);
            doForAllMaximizersOfTargetAndAccount(_vid, _from, realizeTargetShares);
            maximizerEarningsOffset[_from][_vid] -= shareOffset;
            maximizerEarningsOffset[_to][_vid] += shareOffset;
        }
    }
    //For some maximizer, transfers target ERC1155 shares to the user and offsets them
    function realizeTargetShares(uint _vid, address _account) internal returns (uint amount) {
        amount = targetSharesFromMaximizer(_vid, _account);
        console.log("RTS amount:", amount);
        console.log("RTS account maximizer balance:", balanceOf(_account, _vid), rawBalanceOf(_account, _vid));
        console.log("RTS account target balance:", balanceOf(_account, _vid >> 16), rawBalanceOf(_account, _vid >> 16));
        console.log("RTS maximizer target balance:", balanceOf(address(strat(_vid)), _vid >> 16), rawBalanceOf(address(strat(_vid)), _vid >> 16));
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
