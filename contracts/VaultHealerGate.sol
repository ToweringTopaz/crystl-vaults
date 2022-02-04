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
            IStrategy vaultStrat = strat(_vid);

            uint256 wantLockedBefore = vaultStrat.wantLockedTotal();

            // we call an earn on the vault before we action the _deposit
            _doEarn(_vid); 

            // we make the deposit
            uint256 vidSharesAdded = vaultStrat.deposit(_wantAmt, totalSupply(_vid));
            
            // if this is a maximizer vault, do these extra steps
            if (vault.targetVid != 0 && wantLockedBefore > 0) { 
                UpdateOffsetsOnDeposit(_vid, _to, vidSharesAdded);
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

        IStrategy vaultStrat = strat(_vid);

        (uint256 vidSharesRemoved, uint256 wantAmt) = vaultStrat.withdraw(_wantAmt, balanceOf(_from, _vid), totalSupply(_vid));

        if (vault.targetVid != 0 && vaultStrat.wantLockedTotal() > 0) {
            withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(_vid, _from, vidSharesRemoved);
        }

        //burn the tokens equal to vidSharesRemoved todo should this be here, or higher up?
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
                vault.want.safeTransferFrom(address(vaultStrat), feeReceiver, feeAmt); //todo: zap to correct fee token
            }
        } catch {}

        //this call transfers wantTokens from the strat to the user
        vault.want.safeTransferFrom(address(vaultStrat), _to, wantAmt);

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

                    withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(vid, from, underlyingValue);

                    UpdateOffsetsOnDeposit(vid, to, underlyingValue); //todo should this be from or to?????
                }

            }
        }
    }
        
    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function UpdateOffsetsOnDeposit(uint256 _vid, address _from, uint256 _vidSharesAdded) internal {
        Vault.Info storage vault = _vaultInfo[_vid];
        IStrategy vaultStrat = strat(_vid);

        //calculate the offset for this particular deposit
        uint256 targetVidSharesOwnedByMaxiBefore = balanceOf(address(vaultStrat), vault.targetVid) + vault.totalMaximizerEarningsOffset;
        uint256 targetVidTokenOffset = _vidSharesAdded * targetVidSharesOwnedByMaxiBefore / totalSupply(_vid); 

        // increment the offsets for user and for vid
        vault.user[_from].maximizerEarningsOffset += targetVidTokenOffset;
        vault.totalMaximizerEarningsOffset += targetVidTokenOffset; 
    }

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(uint256 _vid, address _from, uint256 _vidSharesRemoved) internal {
        Vault.Info storage vault = _vaultInfo[_vid];
        Vault.Info storage target = _vaultInfo[vault.targetVid];
        IStrategy vaultStrat = strat(_vid);
        IStrategy targetStrat = strat(vault.targetVid);

        // calculate the amount of targetVid token to be withdrawn
        uint256 targetVidAmount = _vidSharesRemoved
            * (targetStrat.wantLockedTotal() + vault.totalMaximizerEarningsOffset)
            / totalSupply(_vid) 
            - vault.user[_from].maximizerEarningsOffset * _vidSharesRemoved / balanceOf(_from, _vid);
        
        // withdraw proportional amount of target vault token from targetVault()
        if (targetVidAmount > 0) {
            // withdraw an amount of reward token from the target vault proportional to the users withdrawal from the main vault
            vaultStrat.withdrawMaximizerReward(vault.targetVid, targetVidAmount);
            target.want.safeTransferFrom(address(vaultStrat), _from, target.want.balanceOf(address(vaultStrat)));
                        
            // update the offsets for user and for vid
            vault.totalMaximizerEarningsOffset -= (vault.user[_from].maximizerEarningsOffset * _vidSharesRemoved / balanceOf(_from, _vid)); //todo this is the case for withdrawAll, what about withdrawSome?
            vault.user[_from].maximizerEarningsOffset -= (vault.user[_from].maximizerEarningsOffset * _vidSharesRemoved / balanceOf(_from, _vid)); //todo this is the case for withdrawAll, what about withdrawSome?
            }
        }

}
