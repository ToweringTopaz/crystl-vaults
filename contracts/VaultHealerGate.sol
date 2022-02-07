// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerBase.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//Handles "gate" functions like deposit/withdraw
abstract contract VaultHealerGate is VaultHealerBase {
    using SafeERC20 for IERC20;
    
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint112 amount;
    }
    PendingDeposit[] private pendingDeposits; //LIFO stack, avoiding complications with maximizers

    event Deposit(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Withdraw(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Earned(uint256 indexed vid, uint256 wantAmountEarned);

    function earn(uint256[] calldata vids) external nonReentrant {
        for (uint i; i < vids.length; i++) {
            uint vid = vids[i];
            if (!paused(vid)) _earn(vid);
        }
    }

    //performs earn even if it's not been long enough
    function _earn(uint256 vid) internal {
        Vault.Info storage vault = _vaultInfo[vid];
        uint32 lastEarnBlock = vault.lastEarnBlock;
        
        if (lastEarnBlock == block.number) return; //earn only once per block ever
        uint lock = _lock;
        _lock = vid; //permit reentrant calls by this vault only
        try strat(vid).earn(vaultFeeManager.getEarnFees(vid)) returns (bool success, uint256 wantLockedTotal) {
            if (success) {                
                updateWantLockedLast(vault, vid, wantLockedTotal);
            }
        } catch {}
        vault.lastEarnBlock = uint32(block.number);
        _lock = lock; //reset reentrancy state
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
        if (_wantAmt > 0) {
            pendingDeposits.push() = PendingDeposit({
                token: vault.want,
                from: _from,
                amount: uint112(_wantAmt)
            });
            IStrategy strategy = strat(_vid);
            _earn(_vid); 

            (uint256 wantAdded, uint256 sharesAdded) = strategy.deposit(_wantAmt, totalSupply(_vid));
            _wantAmt = wantAdded;
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
        _earn(_vid);

        IStrategy strategy = strat(_vid);

        (uint256 sharesRemoved, uint256 wantAmt) = strategy.withdraw(_wantAmt, balanceOf(_from, _vid), totalSupply(_vid));
        _wantAmt = wantAmt;

        //burn the tokens equal to sharesRemoved
        _burn(
            _from,
            _vid,
            sharesRemoved
        );
        
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

        emit Withdraw(_from, _to, _vid, wantAmt); //todo shouldn't this emit wantAmt?
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

    function updateWantLockedLast(Vault.Info storage vault, uint vid, uint wantLockedTotal) private {
        uint wantLockedLastUpdate = vault.wantLockedLastUpdate;
        if (wantLockedTotal > wantLockedLastUpdate) {
            require(wantLockedTotal < type(uint112).max, "VH: wantLockedTotal overflow");
            emit Earned(vid, wantLockedTotal - wantLockedLastUpdate);
            vault.wantLockedLastUpdate = uint112(wantLockedTotal);
        }
    }
}
