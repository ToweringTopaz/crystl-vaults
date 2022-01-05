// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerEarn.sol";

//Handles "gate" functions like deposit/withdraw
abstract contract VaultHealerGate is VaultHealerEarn {
    using SafeERC20 for IERC20;
    
    struct TransferData { //All stats in underlying want tokens
        uint256 deposits;
        uint256 withdrawals;
        uint256 transfersIn;
        uint256 transfersOut;
    }
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint256 amount;
    }
    mapping(bytes32 => TransferData) private _transferData;
    PendingDeposit[] private pendingDeposits; //LIFO stack, avoiding complications with maximizers

    event Deposit(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Withdraw(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);

    function transferData(uint vid, address user) internal view returns (TransferData storage) {
        return _transferData[keccak256(abi.encodePacked(vid, user))]; //what does this do?
    }
    function userTotals(uint256 vid, address user) external view 
        returns (TransferData memory stats, int256 earned) 
    {
        stats = transferData(vid, user);
        
        uint _ts = totalSupply(vid);
        uint staked = _ts == 0 ? 0 : balanceOf(user, vid) * _vaultInfo[vid].strat.wantLockedTotal() / _ts;
        earned = int(stats.withdrawals + staked + stats.transfersOut) - int(stats.deposits + stats.transfersIn);
    }
    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _tokenID, uint256 _wantAmt) external nonReentrant {
        _deposit(_tokenID, _wantAmt, _msgSender(), _msgSender());
    }

    // For depositing for other users
    function deposit(uint256 _tokenID, uint256 _wantAmt, address _to) external nonReentrant {
        _deposit(_tokenID, _wantAmt, _msgSender(), _to);
    }

    function _deposit(uint256 _tokenID, uint256 _wantAmt, address _from, address _to) whenNotPaused(vaultOf(_tokenID)) private {
        VaultInfo storage vault = _vaultInfo[_vid];
        //require(vault.want.allowance(_from, address(this)) >= _wantAmt, "VH: Insufficient allowance for deposit");
        //require(address(vault.strat) != address(0), "That strategy does not exist");

        if (_wantAmt > 0) {
            pendingDeposits.push() = PendingDeposit({ //todo: understand better what this does
                token: vault.want,
                from: _from,
                amount: _wantAmt
            });

            _earnBeforeTx(_vid); 

            uint256 sharesAdded = vault.strat.deposit(_wantAmt, totalSupply(_vid));
            //we mint tokens for the user via the 1155 contract
            _mint(
                _to,
                _vid, //use the vid of the strategy 
                sharesAdded,
                hex'' //leave this blank for now
            );
            //update the user's data for earn tracking purposes
            transferData(_vid, _to).deposits += _wantAmt - pendingDeposits[pendingDeposits.length - 1].amount;
            
            pendingDeposits.pop();
        }
        emit Deposit(_from, _to, _vid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _tokenID, uint256 _wantAmt) external nonReentrant {
        _withdraw(_tokenID, _wantAmt, _msgSender(), _msgSender());
    }

    // For withdrawing to other address
    function withdrawTo(uint256 _tokenID, uint256 _wantAmt, address _to) external nonReentrant {
        _withdraw(_vid, _wantAmt, _msgSender(), _to);
    }

    function _withdraw(uint256 _tokenID, uint256 _wantAmt, address _from, address _to) private {
        assert (_from == _to || _msgSender() == _from); //security check
        uint32 vid = uint32(_id);
        VaultInfo storage vault = _vaultInfo[vid];
        require(balanceOf(_from, _id) > 0, "User has 0 shares");

        if (!paused(vid)) _earnBeforeTx(vid);

        (uint256 sharesRemoved, uint256 wantAmt) = vault.strat.withdraw(_wantAmt, balanceOf(_from, vid), totalSupply(vid));

        //burn the tokens equal to sharesRemoved
        _burn(
            _from,
            _id,
            sharesRemoved
        );
        //updates transferData for this user, so that we are accurately tracking their earn
        transferData(_id, _from).withdrawals += wantAmt;
        
        //withdraw fee is implemented here
        VaultFee storage withdrawFee = getWithdrawFee(vid);
        address feeReceiver = withdrawFee.receiver;
        uint16 feeRate = withdrawFee.rate;
        if (feeReceiver != address(0) && feeRate > 0 && !paused(vid)) { //waive withdrawal fee on paused vaults as there's generally something wrong
            uint feeAmt = wantAmt * feeRate / 10000;
            wantAmt -= feeAmt;
            vault.want.safeTransferFrom(address(vault.strat), feeReceiver, feeAmt); //todo: zap to correct fee token
        }
        
        //this call transfers wantTokens from the strat to the user
        vault.want.safeTransferFrom(address(vault.strat), _to, wantAmt);

        emit Withdraw(_from, _to, vid, _wantAmt);
    }

    // Withdraw everything from vault for yourself
    function withdrawAll(uint256 _vid) external nonReentrant {
        _withdraw(_vid, type(uint256).max, _msgSender(), _msgSender());
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint _amount) external onlyRole(STRATEGY) {
        PendingDeposit storage pendingDeposit = pendingDeposits[pendingDeposits.length - 1];
        pendingDeposit.amount -= _amount;
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
                uint underlyingValue = amounts[i] * _vaultInfo[vid].strat.wantLockedTotal() / totalSupply(vid);
                transferData(vid, from).transfersOut += underlyingValue;
                transferData(vid, to).transfersIn += underlyingValue;
            }
        }
    }

}
