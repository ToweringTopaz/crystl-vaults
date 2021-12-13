// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealer.sol";

import "./BaseStrategySwapLogic.sol";
import "./libs/IStrategy.sol";

//Deposit and withdraw for a secure VaultHealer-based system. VaultHealer is responsible for tracking user shares.
abstract contract BaseStrategyVaultHealer is BaseStrategySwapLogic {
    using SafeERC20 for IERC20;
    using LibVaultConfig for VaultFees;
    using LibVaultSwaps for VaultFees;    
    
    VaultHealer immutable public vaultHealer; //why is this immutable?
    IStrategy public maximizerVault;
    address public boostPoolAddress;

    bool public isMaximizer;

    IERC20 maximizerRewardToken;

    constructor(address _vaultHealerAddress) {
        vaultHealer = VaultHealer(_vaultHealerAddress);
        settings.magnetite = Magnetite(_vaultHealerAddress);
    }
    
    function sharesTotal() external view returns (uint) {
        return vaultHealer.sharesTotal(address(this));
    }
    
    //The owner of the connected vaulthealer gets administrative power in the strategy, automatically.
    modifier onlyGov() override {
        require(msg.sender == vaultHealer.owner() || msg.sender == address(vaultHealer), "!gov");
        _;
    }
    modifier onlyVaultHealer {
        require(msg.sender == address(vaultHealer), "!vaulthealer");
        _;
    }
    //Earn should be called with the vaulthealer, which has nonReentrant checks on deposit, withdraw, and earn.
    function earn(address _to) external onlyVaultHealer {
        _earn(_to);    
    }

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(address _from, address /*_to*/, uint256 _wantAmt, uint256 _sharesTotal) external onlyVaultHealer returns (uint256 sharesAdded) {
        _earn(_from); //earn before deposit prevents abuse


        if (_wantAmt < settings.dust) return 0; //do nothing if nothing is requested
        
        uint256 wantLockedBefore = wantLockedTotal();

        if (address(maximizerVault) != address(0) && wantLockedBefore > 0) { //
            UpdatePoolAndRewarddebtOnDeposit(_from, _wantAmt);
            }

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        vaultHealer.executePendingDeposit(address(this), _wantAmt);
        _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        sharesAdded = wantLockedTotal() - wantLockedBefore;
        if (_sharesTotal > 0) { //mulDiv prevents overflow for certain tokens/amounts
            sharesAdded = FullMath.mulDiv(sharesAdded, _sharesTotal, wantLockedBefore);
        }
        require(sharesAdded > settings.dust, "deposit: no/dust shares added");
    }

    function UpdatePoolAndRewarddebtOnDeposit (address _from, uint256 _wantAmt) public {
        vaultHealer.user.rewardDebt[_from] += _wantAmt * vaultHealer.pool.accRewardTokensPerShare / 1e30; //todo: should this go here or higher up? above the strat.deposit?

        vaultHealer.pool.accRewardTokensPerShare += (maximizerVault.wantLockedTotal() - vaultHealer.pool.balanceCrystlCompounderLastUpdate) * 1e30 / wantLockedTotal(); //multiply or divide by 1e30??

        vaultHealer.pool.balanceCrystlCompounderLastUpdate = maximizerVault.wantLockedTotal(); //todo: move these two lines to prevent re-entrancy? but then how do they calc properly?

    }

    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(address _from, address /*_to*/, uint _wantAmt, uint _userShares, uint _sharesTotal) external onlyVaultHealer returns (uint sharesRemoved, uint wantAmt) {
        //User's balance, in want tokens
        uint wantBal = _wantBalance(); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + vaultSharesTotal(); //todo: why is this different to deposit function????????????
        uint256 userWant = FullMath.mulDiv(_userShares, wantLockedBefore, _sharesTotal) ;

        //todo: should the earn go inside the conditional? i.e. do we need to earn if it's not a maximizer? I think so actually...
        _earn(_from); //earn before withdraw is only fair to withdrawing user - they get the crysl rewards they've earned

        // should call earn on CC too? again, to be fair to individual who is withdrawing? Or what? they should get the rewards anyway right when we withdraw from the CC? yes, because it's using this same withdraw function!
        if (address(maximizerVault) != address(0) && wantLockedBefore > 0) {
            UpdatePoolAndWithdrawCrystlOnWithdrawal(_from, _wantAmt, userWant);
        }

        // user requested all, very nearly all, or more than their balance, so withdraw all
        if (_wantAmt + settings.dust > userWant)
            _wantAmt = userWant;
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantBal) {
            _vaultWithdraw(_wantAmt - wantBal);
            
            wantBal = _wantBalance();   
        }
        
        //Account for reflect, pool withdraw fee, etc; charge these to user
        uint wantLockedAfter = wantLockedTotal();
        uint withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;
        
        //Calculate shares to remove
        sharesRemoved = FullMath.mulDivRoundingUp(
            _wantAmt + withdrawSlippage,
            _sharesTotal,
            wantLockedBefore
        );
        
        //Get final withdrawal amount
        if (sharesRemoved > _userShares) sharesRemoved = _userShares;
        _wantAmt = FullMath.mulDiv(sharesRemoved, wantLockedBefore, _sharesTotal) - withdrawSlippage;
        
        if (_wantAmt > wantBal) _wantAmt = wantBal;
        require(_wantAmt > 0, "nothing to withdraw after slippage");
        
        wantToken.safeIncreaseAllowance(address(vaultHealer), _wantAmt);
        return (sharesRemoved, _wantAmt);
    }

    function UpdatePoolAndWithdrawCrystlOnWithdrawal(address _from, uint256 _wantAmt, uint256 _userWant) public {

        accRewardTokensPerShare += (maximizerVault.wantLockedTotal() - balanceCrystlCompounderLastUpdate) * 1e30 / wantLockedTotal(); //multiply or divide by 1e30??


        //calculate total crystl amount this user owns (pending is not quite the right term)
        uint256 crystlShare = _wantAmt * accRewardTokensPerShare / 1e30 - rewardDebt[_from] * _wantAmt / _userWant; //can I include crystl that's in pending rewards in the staking pool here?


        //withdraw proportional amount of crystl from maximizerVault
        if (crystlShare > 0) {
            vaultHealer.withdraw(3, crystlShare);
            maximizerRewardToken.safeTransfer(_from, maximizerRewardToken.balanceOf(address(this))); //check that this address is correct
            rewardDebt[_from] -= rewardDebt[_from] * _wantAmt / _userWant;
            }
        balanceCrystlCompounderLastUpdate = maximizerVault.wantLockedTotal(); //todo: move these two lines to prevent re-entrancy? but then how do they calc properly?
    }

    function _pause() internal override {} //no-op, since vaulthealer manages paused status
    function _unpause() internal override {}
    function paused() public view override returns (bool) {
        return vaultHealer.paused(address(this));
    }

    function setBoostPoolAddress(address _boostPoolAddress) external {
        boostPoolAddress = _boostPoolAddress;
    }

    function getRewardDebt(address _user) external view returns (uint256) {
        return rewardDebt[_user];
    }

    function increaseRewardDebt(address _user, uint256 amount) public {
        rewardDebt[_user] += amount;
    }

function CheckIsMaximizer() external view returns (bool) {
    return isMaximizer;
}

}