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

    function userTotals(uint256 vid, address user) external view 
        returns (Vault.TransferData memory stats, int256 earned) 
    {
        stats = _vaultInfo[vid].user[user].stats;
        
        uint _ts = totalSupply(vid);
        uint staked = _ts == 0 ? 0 : balanceOf(user, vid) * strat(vid).wantLockedTotal() / _ts;
        earned = int(stats.withdrawals + staked + stats.transfersOut) - int(uint(stats.deposits + stats.transfersIn));
    }
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
        //require(vault.want.allowance(_from, address(this)) >= _wantAmt, "VH: Insufficient allowance for deposit");
        //require(address(vault.strat) != address(0), "That strategy does not exist");

        if (_wantAmt > 0) {
            pendingDeposits.push() = PendingDeposit({ //todo: understand better what this does
                token: vault.want,
                from: _from,
                amount: uint112(_wantAmt)
            });
            IStrategy strategy = strat(_vid);
            uint256 wantLockedBefore = strategy.wantLockedTotal();

            _doEarn(_vid); 

            if (vault.targetVid != 0 && wantLockedBefore > 0) { //
                UpdatePoolAndRewarddebtOnDeposit(_vid, _to, _wantAmt);
            }

            uint256 sharesAdded = strategy.deposit(_wantAmt, totalSupply(_vid));
            //we mint tokens for the user via the 1155 contract
            _mint(
                _to,
                _vid, //use the vid of the strategy 
                sharesAdded,
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
            UpdatePoolAndWithdrawCrystlOnWithdrawal(_vid, _from, _wantAmt);
        }

        (uint256 sharesRemoved, uint256 wantAmt) = strategy.withdraw(_wantAmt, balanceOf(_from, _vid), totalSupply(_vid));

        //burn the tokens equal to sharesRemoved
        _burn(
            _from,
            _vid,
            sharesRemoved
        );
        //updates transferData for this user, so that we are accurately tracking their earn
        vault.user[_from].stats.withdrawals += uint128(wantAmt);
        
        //withdraw fee is implemented here
        Vault.Fee storage withdrawFee = getWithdrawFee(_vid);
        address feeReceiver = withdrawFee.receiver;
        uint16 feeRate = withdrawFee.rate;
        if (feeReceiver != address(0) && feeRate > 0 && !paused(_vid)) { //waive withdrawal fee on paused vaults as there's generally something wrong
            uint feeAmt = wantAmt * feeRate / 10000;
            wantAmt -= feeAmt;
            vault.want.safeTransferFrom(address(strategy), feeReceiver, feeAmt); //todo: zap to correct fee token
        }

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
                uint128 underlyingValue = uint128(amounts[i] * strat(vid).wantLockedTotal() / totalSupply(vid));
                _vaultInfo[vid].user[from].stats.transfersOut += underlyingValue;
                _vaultInfo[vid].user[to].stats.transfersIn += underlyingValue;

                if (_vaultInfo[vid].targetVid != 0) {
                    _doEarn(vid); //does it matter who calls the earn? -- this one credits msg.sender, the account responsible for paying the gas

                    UpdatePoolAndWithdrawCrystlOnWithdrawal(vid, from, underlyingValue);

                    UpdatePoolAndRewarddebtOnDeposit(vid, to, underlyingValue);
                    }

            }
        }
    }

    function UpdatePoolAndRewarddebtOnDeposit (uint256 _vid, address _from, uint256 _wantAmt) internal {
        Vault.Info storage vault = _vaultInfo[_vid];
        uint targetVid = vault.targetVid;
        IStrategy targetStrat = strat(targetVid);
        vault.user[_from].rewardDebt += _wantAmt * vault.accRewardTokensPerShare / 1e30;
        uint targetWantLocked = targetStrat.wantLockedTotal();
        require (targetWantLocked <= type(uint112).max, "VH: wantLockedTotal overflow");

        vault.accRewardTokensPerShare += uint112((targetWantLocked - vault.balanceCrystlCompounderLastUpdate) * 1e30 / strat(_vid).wantLockedTotal()); 

        vault.balanceCrystlCompounderLastUpdate = uint112(targetWantLocked); //todo: move these two lines to prevent re-entrancy? but then how do they calc properly?

    }

    function UpdatePoolAndWithdrawCrystlOnWithdrawal(uint256 _vid, address _from, uint256 _wantAmt) internal {
        Vault.Info storage vault = _vaultInfo[_vid];
        uint targetVid = vault.targetVid;
        IStrategy vaultStrat = strat(_vid);
        Vault.Info storage target = _vaultInfo[vault.targetVid];
        IStrategy targetStrat = strat(targetVid);
        uint targetWantLocked = targetStrat.wantLockedTotal();
        require (targetWantLocked <= type(uint112).max, "VH: wantLockedTotal overflow");

        vault.accRewardTokensPerShare += uint112((targetWantLocked - vault.balanceCrystlCompounderLastUpdate) * 1e30 / vaultStrat.wantLockedTotal());
        //calculate total crystl amount this user owns
        uint256 crystlShare = _wantAmt * vault.accRewardTokensPerShare / 1e30 - vault.user[_from].rewardDebt * _wantAmt / balanceOf(_from, _vid); 
        //withdraw proportional amount of crystl from targetVault()
        if (crystlShare > 0) {
            vaultStrat.withdrawMaximizerReward(vault.targetVid, crystlShare);
            target.want.safeTransferFrom(address(vaultStrat), _from, target.want.balanceOf(address(vaultStrat)));
            vault.user[_from].rewardDebt -= vault.user[_from].rewardDebt * _wantAmt / balanceOf(_from, _vid);
            }
        vault.balanceCrystlCompounderLastUpdate = uint112(targetWantLocked); //todo: move these two lines to prevent re-entrancy? but then how do they calc properly?
    }
}
