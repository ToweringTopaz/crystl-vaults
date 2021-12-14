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
    
    // Info of each user.
    // struct UserInfo {
    //     uint256 rewardDebt;
    // //     // uint256 totalDeposits;
    // //     // uint256 totalWithdrawals;
    // //     // mapping (address => uint256) allowances; //for ERC20 transfers
    // //     // bytes data;
    // }

    VaultHealer immutable public vaultHealer; //why is this immutable?
    IStrategy public maximizerVault;
    address public boostPoolAddress;
    uint public immutable pid;
    bool public isMaximizer;

    IERC20 public maximizerRewardToken;

    constructor(address _vaultHealerAddress, uint256 _pid) {
        vaultHealer = VaultHealer(_vaultHealerAddress);
        settings.magnetite = Magnetite(_vaultHealerAddress);
        pid = _pid;
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
        // _earn(_from); //earn before deposit prevents abuse
        uint wantBal = _wantBalance(); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + vaultSharesTotal(); //todo: why is this different to deposit function????????????

        if (_wantAmt < settings.dust) return 0; //do nothing if nothing is requested

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



    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(address /*_from*/, address /*_to*/, uint _wantAmt, uint _userShares, uint _sharesTotal) external onlyVaultHealer returns (uint sharesRemoved, uint wantAmt) {
        //User's balance, in want tokens
        uint wantBal = _wantBalance(); ///todo: why would there be want sitting in the strat contract?
        uint wantLockedBefore = wantBal + vaultSharesTotal(); //todo: why is this different to deposit function????????????
        uint256 userWant = FullMath.mulDiv(_userShares, wantLockedBefore, _sharesTotal) ;

        //todo: should the earn go inside the conditional? i.e. do we need to earn if it's not a maximizer? I think so actually...
        // _earn(_from); //earn before withdraw is only fair to withdrawing user - they get the crysl rewards they've earned


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

    function _pause() internal override {} //no-op, since vaulthealer manages paused status
    function _unpause() internal override {}
    function paused() public view override returns (bool) {
        return vaultHealer.paused(address(this));
    }

    function setBoostPoolAddress(address _boostPoolAddress) external {
        boostPoolAddress = _boostPoolAddress;
    }

    // function getRewardDebt(address _user) external view returns (uint256) {
    //     return vaultHealer.rewardDebt[pid][_user];
    // }

    // function increaseRewardDebt(address _user, uint256 amount) public {
    //     vaultHealer.rewardDebt[pid][_user] += amount;
    // }

function CheckIsMaximizer() external view returns (bool) {
    return isMaximizer;
}

}