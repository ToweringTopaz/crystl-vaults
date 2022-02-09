// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerBase.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract VaultHealerGate is VaultHealerBase {
    using SafeERC20 for IERC20;
    
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint112 amount;
    }

    mapping(address => mapping(uint256 => uint112)) public maximizerEarningsOffset;
    mapping(uint256 => uint112) public totalMaximizerEarningsOffset;

    PendingDeposit[] private pendingDeposits; //LIFO stack, avoiding complications with maximizers

    event Deposit(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Withdraw(address indexed from, address indexed to, uint256 indexed vid, uint256 amount);
    event Earned(uint256 indexed vid, uint256 wantAmountEarned);

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
                emit Earned(vid, wantLockedTotal - vault.wantLockedLastUpdate);
                vault.wantLockedLastUpdate = uint112(wantLockedTotal);
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
        VaultInfo storage vault = vaultInfo[_vid];

        pendingDeposits.push() = PendingDeposit({
            token: vault.want,
            from: _from,
            amount: uint112(_wantAmt)
        });
        
        IStrategy vaultStrat = strat(_vid);

        // we call an earn on the vault before we action the _deposit
        _earn(_vid); 

        // we make the deposit
        (uint256 wantAdded, uint256 vidSharesAdded) = vaultStrat.deposit(_wantAmt, totalSupply(_vid));

        // if this is a maximizer vault, do these extra steps
        if (_vid >> 32 > 0)
            UpdateOffsetsOnDeposit(_vid, _to, vidSharesAdded);

        //we mint tokens for the user via the 1155 contract
        _mint(
            _to,
            _vid, //use the vid of the strategy 
            vidSharesAdded,
            hex'' //leave this blank for now
        );
            
        pendingDeposits.pop();

        vault.wantLockedLastUpdate += uint112(wantAdded);
        emit Deposit(_from, _to, _vid, wantAdded);
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
        VaultInfo storage vault = vaultInfo[_vid];
        require(balanceOf(_from, _vid) > 0, "User has 0 shares");
        _earn(_vid);

        IStrategy vaultStrat = strat(_vid);

        (uint256 vidSharesRemoved, uint256 wantAmt) = vaultStrat.withdraw(_wantAmt, balanceOf(_from, _vid), totalSupply(_vid));

        if (_vid >> 32 > 0) {
            withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(_vid, _from, vidSharesRemoved);
        }

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

                if (vid >> 32 > 0) {
                    _earn(vid);
                    uint128 underlyingValue = uint128(amounts[i] * strat(vid).wantLockedTotal() / totalSupply(vid));
                    
                    withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(vid, from, underlyingValue);

                    UpdateOffsetsOnDeposit(vid, to, underlyingValue); //todo should this be from or to?????
                }

            }
        }
    }

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function UpdateOffsetsOnDeposit(uint256 _vid, address _from, uint256 _vidSharesAdded) internal {
        IStrategy vaultStrat = strat(_vid);
        uint256 targetVid = _vid >> 32;

        //calculate the offset for this particular deposit
        uint256 targetVidSharesOwnedByMaxiBefore = balanceOf(address(vaultStrat), targetVid) + totalMaximizerEarningsOffset[_vid];
        uint112 targetVidTokenOffset = uint112(_vidSharesAdded * targetVidSharesOwnedByMaxiBefore / totalSupply(_vid)); 

        // increment the offsets for user and for vid
        maximizerEarningsOffset[_from][_vid] += targetVidTokenOffset;
        totalMaximizerEarningsOffset[_vid] += targetVidTokenOffset; 
    }

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function withdrawTargetTokenAndUpdateOffsetsOnWithdrawal(uint256 _vid, address _from, uint256 _vidSharesRemoved) internal {
        uint targetVid = _vid >> 32;
        VaultInfo storage target = vaultInfo[targetVid];
        
        IStrategy vaultStrat = strat(_vid);
        IStrategy targetStrat = strat(targetVid);

        // calculate the amount of targetVid token to be withdrawn
        uint256 targetVidAmount = _vidSharesRemoved
            * (targetStrat.wantLockedTotal() + totalMaximizerEarningsOffset[_vid])
            / totalSupply(_vid) 
            - maximizerEarningsOffset[_from][_vid] * _vidSharesRemoved / balanceOf(_from, _vid);
        
        // withdraw proportional amount of target vault token from targetVault()
        if (targetVidAmount > 0) {
            // withdraw an amount of reward token from the target vault proportional to the users withdrawal from the main vault
            vaultStrat.withdrawMaximizerReward(targetVid, targetVidAmount);
            target.want.safeTransferFrom(address(vaultStrat), _from, target.want.balanceOf(address(vaultStrat)));
                        
            // update the offsets for user and for vid
            totalMaximizerEarningsOffset[_vid] -= uint112(maximizerEarningsOffset[_from][_vid] * _vidSharesRemoved / balanceOf(_from, _vid)); //todo this is the case for withdrawAll, what about withdrawSome?
            maximizerEarningsOffset[_from][_vid] -= uint112(maximizerEarningsOffset[_from][_vid] * _vidSharesRemoved / balanceOf(_from, _vid)); //todo this is the case for withdrawAll, what about withdrawSome?
            }
        }

}
