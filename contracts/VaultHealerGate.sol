// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerEarn.sol";

//Handles "gate" functions like deposit/withdraw
abstract contract VaultHealerGate is VaultHealerEarn {
    using SafeERC20 for IERC20;
    
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint112 amount;
    }
    PendingDeposit[] private pendingDeposits; //LIFO stack, avoiding complications with maximizers

    event Deposit(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Withdraw(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _vid, uint256 _wantAmt) external whenNotPaused(_vid) {
        _deposit(_vid, _wantAmt, msg.sender, msg.sender);
    }

    // For depositing for other users
    function deposit(uint256 _vid, uint256 _wantAmt, address _to) external whenNotPaused(_vid) {
        _deposit(_vid, _wantAmt, msg.sender, _to);
    }

    function _deposit(uint256 _vid, uint256 _wantAmt, address _from, address _to) private reentrantOnlyByStrategy(_vid) {
        Vault.Info storage vault = _vaultInfo[_vid];
        if (_wantAmt > 0) {
            pendingDeposits.push() = PendingDeposit({
                token: vault.want,
                from: _from,
                amount: uint112(_wantAmt)
            });
            IStrategy strategy = strat(_vid);

            uint256 wantLockedBefore = strategy.wantLockedTotal();

            _doEarn(_vid); 

            uint256 totalSharesBeforeDeposit = totalSupply(_vid);

            uint256 vidSharesAdded = strategy.deposit(_wantAmt, totalVidSharesBeforeDeposit);

            if (vault.targetVid != 0 && wantLockedBefore > 0) { // if this is a maximizer vault, do these extra steps
                IStrategy targetStrategy = strat(vault.targetVid);
                uint256 targetVidSharesOwnedByMaxiBefore = targetStrategy.balanceOf(_vid) + vault.offset; //have to add in the offset here for the strategy
                int256 targetVidTokenOffset = vidSharesAdded * targetVidSharesOwnedByMaxiBefore / totalVidSharesBeforeDeposit; //this will need to move below the deposit step - implications?
                int256 user.offset -= targetVidTokenOffset; //todo where to save this?
                int256 vault.offset += targetVidTokenOffset; //todo where to save this?
            }

            //we mint tokens for the user via the 1155 contract
            _mint(
                _to,
                _vid, //use the vid of the strategy 
                vidSharesAdded,
                hex'' //leave this blank for now
            );
            //update the user's data for earn tracking purposes
            vault.user[_to].stats.deposits += uint128(_wantAmt - pendingDeposits[pendingDeposits.length - 1].amount);
            
            pendingDeposits.pop();
        }
        emit Deposit(_from, _to, _vid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _vid, uint256 _wantAmt) external {
        _withdraw(_vid, _wantAmt, msg.sender, msg.sender);
    }

    // For withdrawing to other address
    function withdraw(uint256 _vid, uint256 _wantAmt, address _to) external {
        _withdraw(_vid, _wantAmt, msg.sender, _to);
    }

    function withdrawFrom(uint256 _vid, uint256 _wantAmt, address _from, address _to) external {
        require(
            _from == msg.sender || isApprovedForAll(_from, msg.sender),
            "ERC1155: caller is not owner nor approved"
        );
        _withdraw(_vid, _wantAmt, _from, _to);
    }

    function _withdraw(uint256 _vid, uint256 _wantAmt, address _from, address _to) private reentrantOnlyByStrategy(_vid) {
        Vault.Info storage vault = _vaultInfo[_vid];
        require(balanceOf(_from, _vid) > 0, "User has 0 shares");
        _doEarn(_vid);

        IStrategy strategy = strat(_vid);
        if (vault.targetVid != 0 && strategy.wantLockedTotal() > 0) {
            IStrategy targetStrategy = strat(vault.targetVid);
            uint256 targetVidSharesOwnedByMaxiBefore = targetStrategy.balanceOf(_vid) + vault.offset; //have to add in the offset here for the strategy
            int256 targetVidTokenOffset = -vidSharesRemoved * targetVidSharesOwnedByMaxiBefore / totalVidSharesBeforeDeposit; //this will need to move below the deposit step - implications?
            int256 user.offset -= targetVidTokenOffset; //todo where to save this?
            int256 vault.offset += targetVidTokenOffset; //todo where to save this?
            // todo - withdraw crystl proportional to the withdrawal at vid level? Is this still necessary? Must this come first?

            // update the offsets for user and for vid

            // UpdatePoolAndWithdrawCrystlOnWithdrawal(_vid, _from, _wantAmt);
        }

        (uint256 vidSharesRemoved, uint256 wantAmt) = strategy.withdraw(_wantAmt, balanceOf(_from, _vid), totalSupply(_vid));

        //burn the tokens equal to vidSharesRemoved
        _burn(
            _from,
            _vid,
            vidSharesRemoved
        );
        //updates transferData for this user, so that we are accurately tracking their earn
        vault.user[_from].stats.withdrawals += uint128(wantAmt);
        
        //withdraw fee is implemented here
        try vaultFeeManager.getWithdrawFee(_vid) returns (address feeReceiver, uint16 feeRate) {
            //hardcoded 5% max fee rate
            if (feeReceiver != address(0) && feeRate <= 500 && !paused(_vid)) { //waive withdrawal fee on paused vaults as there's generally something wrong
                uint feeAmt = wantAmt * feeRate / 10000;
                wantAmt -= feeAmt;
                vault.want.safeTransferFrom(address(strategy), feeReceiver, feeAmt); //todo: zap to correct fee token
            }
        } catch {}

        //this call transfers wantTokens from the strat to the user
        vault.want.safeTransferFrom(address(strategy), _to, wantAmt);

        emit Withdraw(_from, _to, _vid, _wantAmt); //todo shouldn't this emit wantAmt?
    }

    // Withdraw everything from vault for yourself
    function withdrawAll(uint256 _vid) external {
        _withdraw(_vid, type(uint112).max, msg.sender, msg.sender);
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint112 _amount) external {
        PendingDeposit storage pendingDeposit = pendingDeposits[pendingDeposits.length - 1];
        pendingDeposit.amount -= uint112(_amount);
        pendingDeposit.token.safeTransferFrom(
            pendingDeposit.from,
            _to,
            _amount
        );
    }

function _beforeTokenTransfer(
        address /*operator*/,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory //data
    ) internal virtual override {
        if (from != address(0) && to != address(0)) {
            for (uint i; i < ids.length; i++) {
                uint vid = ids[i];
                uint128 underlyingValue = uint128(amounts[i] * strat(vid).wantLockedTotal() / totalSupply(vid));
                _vaultInfo[vid].user[from].stats.transfersOut += underlyingValue;
                _vaultInfo[vid].user[to].stats.transfersIn += underlyingValue;

                if (_vaultInfo[vid].targetVid != 0) {
                    _doEarn(vid);

                    UpdatePoolAndWithdrawCrystlOnWithdrawal(vid, from, underlyingValue);

                    UpdatePoolAndRewarddebtOnDeposit(vid, to, underlyingValue);
                }

            }
        }
    }
    // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function UpdatePoolAndRewarddebtOnDeposit (uint256 _vid, address _from, uint256 _wantAmt) internal {
        Vault.Info storage vault = _vaultInfo[_vid];
        uint targetVid = vault.targetVid;
        IStrategy targetStrat = strat(targetVid);
        uint targetWantLocked = targetStrat.wantLockedTotal();
        
        // increase accRewardTokensPerShare by: the increase in balance of target vault since last deposit or withdrawal / total shares
        vault.accRewardTokensPerShare += uint256((targetWantLocked - vault.balanceCrystlCompounderLastUpdate) * 1e30 / strat(_vid).wantLockedTotal()); 
            
        // increase the depositing user's rewardDebt
        vault.user[_from].rewardDebt += _wantAmt * vault.accRewardTokensPerShare / 1e30;

        // reset balanceCrystlCompounderLastUpdate to whatever balance the target vault has now
        vault.balanceCrystlCompounderLastUpdate = uint256(targetWantLocked); 
        }
    
    // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function UpdatePoolAndWithdrawCrystlOnWithdrawal(uint256 _vid, address _from, uint256 _wantAmt) internal {
        Vault.Info storage vault = _vaultInfo[_vid];
        uint targetVid = vault.targetVid;
        IStrategy vaultStrat = strat(_vid);
        Vault.Info storage target = _vaultInfo[vault.targetVid];
        IStrategy targetStrat = strat(targetVid);
        uint targetWantLocked = targetStrat.wantLockedTotal();
        if (_wantAmt > balanceOf(_from, _vid)) _wantAmt = balanceOf(_from, _vid);
        
        // increase accRewardTokensPerShare by: the increase in balance of target vault since last deposit or withdrawal / total shares
        vault.accRewardTokensPerShare += uint256((targetWantLocked - vault.balanceCrystlCompounderLastUpdate) * 1e30 / vaultStrat.wantLockedTotal());
        
        // calculate total crystl amount this user owns
        uint256 crystlShare = _wantAmt * vault.accRewardTokensPerShare / 1e30 - vault.user[_from].rewardDebt * _wantAmt / balanceOf(_from, _vid); 

        // withdraw proportional amount of crystl from targetVault()
        if (crystlShare > 0) {
            // withdraw an amount of reward token from the target vault proportional to the users withdrawal from the main vault
            vaultStrat.withdrawMaximizerReward(vault.targetVid, crystlShare);
            target.want.safeTransferFrom(address(vaultStrat), _from, target.want.balanceOf(address(vaultStrat)));
            
            // decrease the depositing user's rewardDebt
            vault.user[_from].rewardDebt -= vault.user[_from].rewardDebt * _wantAmt / balanceOf(_from, _vid); 
            }
        // reset balanceCrystlCompounderLastUpdate to whatever balance the target vault has now
        vault.balanceCrystlCompounderLastUpdate = uint256(targetStrat.wantLockedTotal());
    }
}
