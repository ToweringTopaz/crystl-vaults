// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerEarn.sol";

//Handles "gate" functions like deposit/withdraw
abstract contract VaultHealerGate is VaultHealerEarn {
    using SafeERC20 for IERC20;
    
    struct PendingDeposit {
        IERC20 token;
        uint96 amount0;
        address from;
        uint96 amount1;
    }
    PendingDeposit[] private pendingDeposits; //LIFO stack, avoiding complications with maximizers

    event Deposit(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Withdraw(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint _vid, uint256 _wantAmt) external whenNotPaused(_vid) {
        address[] memory msgSender = _toSingletonArray[msg.sender];
        _deposit(_vid, _toSingletonArray[_wantAmt], msgSender, msgSender);
    }

    // For depositing for other users
    function deposit(uint _vid, uint256 _wantAmt, address _to) external whenNotPaused(_vid) {
        _deposit(_toSingletonArray[_vid], _toSingletonArray[_wantAmt], _toSingletonArray[msg.sender], _toSingletonArray[_to]);
    }

    function deposit(uint256[] memory _vid, uint256[] memory _wantAmt, address[] memory _from, address[] memory _to) {
        require(_wantAmt.length == _from.length == _to.length, "VaultHealer: deposit arrays must be of same length");
        
    }

    function _deposit(uint _vid, uint256 _wantAmt, address[] memory _from, address[] memory _to) private reentrantOnlyByStrategy(_vid) {
        Vault.Info storage vault = _vaultInfo[_vid];
        if (_wantAmt > 0) {
            pendingDeposits.push() = PendingDeposit({ //todo: understand better what this does
                token: vault.want,
                amount0: uint96(_wantAmt << 96), // split amount into two parts so we only write to 2 storage slots instead of 3
                from: _from,
                amount1: uint96(_wantAmt)
            });
            IStrategy strategy = strat(_vid);
            uint256 wantLockedBefore = strategy.wantLockedTotal();

            _earn(_vid); 

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
            
            pendingDeposits.pop();
        }
        emit Deposit(_from, _to, _vid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint _vid, uint256 _wantAmt) external {
        _withdraw(_vid, _wantAmt, msg.sender, msg.sender);
    }

    // For withdrawing to other address
    function withdraw(uint _vid, uint256 _wantAmt, address _to) external {
        _withdraw(_vid, _wantAmt, msg.sender, _to);
    }

    function withdrawFrom(uint _vid, uint256 _wantAmt, address _from, address _to) external {
        require(
            _from == msg.sender || isApprovedForAll(_from, msg.sender),
            "ERC1155: caller is not owner nor approved"
        );
        _withdraw(_vid, _wantAmt, _from, _to);
    }

    function _withdraw(uint _vid, uint256 _wantAmt, address _from, address _to) private reentrantOnlyByStrategy(_vid) {
        Vault.Info storage vault = _vaultInfo[_vid];
        require(balanceOf(_from, _vid) > 0, "User has 0 shares");
        _earn(_vid);

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
        
        //withdraw fee is implemented here
        try vaultFeeManager.getWithdrawFee(_vid) returns (address feeReceiver, uint16 feeRate) {
            //hardcoded 3% max fee rate
            if (feeReceiver != address(0) && feeRate <= 300 && !paused(_vid)) { //waive withdrawal fee on paused vaults as there's generally something wrong
                uint feeAmt = wantAmt * feeRate / 10000;
                wantAmt -= feeAmt;
                vault.want.safeTransferFrom(address(strategy), feeReceiver, feeAmt); //todo: zap to correct fee token
            }
        } catch {}

        //this call transfers wantTokens from the strat to the user
        vault.want.safeTransferFrom(address(strategy), _to, wantAmt);

        emit Withdraw(_from, _to, _vid, wantAmt); //todo shouldn't this emit wantAmt?
    }

    // Withdraw everything from vault for yourself
    function withdrawAll(uint256 _vid) external {
        _withdraw(_vid, type(uint112).max, msg.sender, msg.sender);
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint112 _amount) external {
        PendingDeposit storage pendingDeposit = pendingDeposits[pendingDeposits.length - 1];
        require(_amount < (uint(pendingDeposit.amount0) << 96) | uint(pendingDeposit.amount1), "VH: transfer exceeds pending deposit");
        pendingDeposit.token.safeTransferFrom(
            pendingDeposit.from,
            _to,
            _amount
        );
        pendingDeposits.pop();
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

                    _earn(vid);

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
        vault.balanceCrystlCompounderLastUpdate = uint256(targetWantLocked); //todo: move these two lines to prevent re-entrancy? but then how do they calc properly?
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
        vault.balanceCrystlCompounderLastUpdate = uint256(targetStrat.wantLockedTotal()); //todo: move these two lines to prevent re-entrancy? but then how do they calc properly?
    }

    function _toSingletonArray(address _account) private pure returns (address[] memory account) {
        account = new address[](1);
        account[0] = _account;
    }
    function _toSingletonArray(uint256 _amount) private pure returns (uint256[] memory amount) {
        amount = new address[](1);
        amount[0] = _amount;
    }
}
