// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./VaultHealerBase.sol";
import "hardhat/console.sol";


//Handles "gate" functions like deposit/withdraw
abstract contract VaultHealerGate is VaultHealerBase {
    using SafeERC20 for IERC20;
    
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint256 amount;
    }
    
    PendingDeposit private pendingDeposit;

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt) external nonReentrantPid(_pid) whenNotPaused(_pid) {
        _deposit(_pid, _wantAmt, msg.sender);
    }

    // For depositing for other users
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrantPid(_pid) whenNotPaused(_pid) {
        _deposit(_pid, _wantAmt, _to);
    }

    function _deposit(uint256 _pid, uint256 _wantAmt, address _to) private {
        PoolInfo storage pool = _poolInfo[_pid];
        require(address(pool.strat) != address(0), "That strategy does not exist");

        if (_wantAmt > 0) {
            
            UserInfo storage user = pool.user[_to];
            
            pendingDeposit = PendingDeposit({
                token: pool.want,
                from: msg.sender,
                amount: _wantAmt
            });

            uint256 sharesAdded = pool.strat.deposit(msg.sender, _to, _wantAmt, pool.sharesTotal);
            user.shares += sharesAdded;
            pool.sharesTotal += sharesAdded;
            //we mint tokens for the user via the 1155 contract
            _mint(
                _to,
                _pid, //use the pid of the strategy 
                sharesAdded,
                bytes("0") //leave this blank for now?
            );

            pool.user[_to].totalDeposits = _wantAmt - pendingDeposit.amount;
            delete pendingDeposit;
        }
        emit Deposit(_to, _pid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) external nonReentrantPid(_pid) {
        _withdraw(_pid, _wantAmt, msg.sender);
    }

    // For withdrawing to other address
    function withdraw(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrantPid(_pid) {
        _withdraw(_pid, _wantAmt, _to);
    }

    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) private {
        //create an instance of pool for the relevant pid, and an instance of user for this pool and the msg.sender
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = pool.user[msg.sender];

        IStakingPool stakingPool = IStakingPool(pool.strat.stakingPoolAddress());
        //check that user actually has shares in this pid
        uint256 userStakedAndUnstakedShares = balanceOf(_to, _pid) + stakingPool.userStakedAmount(_to); //TODO - ask TT if there's another way to access this?
        require(userStakedAndUnstakedShares > 0, "User has 0 shares");
        
        //unstake here if need be
        if (_wantAmt > balanceOf(_to, _pid) && stakingPool.userStakedAmount(_to) > 0) { //&&stakingPool exists! check that it's not a zero address?
            stakingPool.withdraw(_wantAmt-balanceOf(_to, _pid));
            }

        //todo: withdraw fee
        console.log(_wantAmt);
        console.log(balanceOf(_to, _pid));
        console.log(user.shares);
        console.log(totalSupply(_pid));
        console.log(pool.sharesTotal);
        //call withdraw on the strat itself - returns sharesRemoved and wantAmt (not _wantAmt) - withdraws wantTokens from the vault to the strat
        //TELL THE STRAT HOW MUCH TO WITHDRAW!! - wantAmt, as long as wantAmt is allowed...
        // (uint256 sharesRemoved, uint256 wantAmt) = pool.strat.withdraw(msg.sender, _to, _wantAmt, user.shares, pool.sharesTotal);
        (uint256 sharesRemoved, uint256 wantAmt) = pool.strat.withdraw(msg.sender, _to, _wantAmt, balanceOf(_to, _pid), totalSupply(_pid));
        console.log(wantAmt);
        //this call transfers wantTokens from the strat to the user
        pool.want.transferFrom(address(pool.strat), _to, wantAmt);
        //updates total withdrawals
        user.totalWithdrawals += wantAmt;
        
        //updates the users shares in this pid
        user.shares -= sharesRemoved;
        //updates total shares in this pid
        pool.sharesTotal -= sharesRemoved;
        //do we need approval to burn?

        //burn the tokens equal to sharesRemoved
        _burn(
            _to,
            _pid,
            sharesRemoved
        );

        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    // Withdraw everything from pool for yourself
    function withdrawAll(uint256 _pid) external nonReentrantPid(_pid) {
        _withdraw(_pid, type(uint256).max, msg.sender);
    }
    
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint _amount) external {
        require(isStrat(msg.sender));
        pendingDeposit.amount -= _amount;
        pendingDeposit.token.safeTransferFrom(
            pendingDeposit.from,
            _to,
            _amount
        );
    }
}
