// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./FullMath.sol";

interface IStrategy {
    function wantAddress() external view returns (address); // Want address
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    function paused() external view returns (bool); // Is strategy paused
    function earn(address _to) external; // Main want token compounding function
    function deposit(address _from, address _to, uint256 _wantAmt) external returns (uint256);
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved);
}
struct UserInfo {
    int shares; // All shares
    uint totalDeposits;
    uint totalWithdrawals;
    mapping (uint => int) sharesOut; //sum(sharesOut) == shares; this is where the pool earnings are compounded to
}

struct PoolInfo {
    IERC20 want; // Address of the want token.
    IStrategy strat; // Strategy address that will auto compound want tokens
    int sharesTotal;
    mapping (address => UserInfo) user;
    mapping (uint => int) sharesIn; //shares earned from a particular pool
    mapping (uint => int) sharesOut; //sum(sharesOut) == sharesTotal; shares deposited here; they compound according to this
}

library LibMaximizer {
    
    function balanceOf(PoolInfo[] storage _poolInfo, uint _pid, address _user) internal view returns (uint) {
        
        PoolInfo storage pool = _poolInfo[_pid];
        int shares = pool.user[_user].shares; //directly owned shares of the pool
        
        for (uint i; i < _poolInfo.length; i++) {
            shares += subBalance(_poolInfo, i, _pid, _user);
        }
        assert(shares >= 0);
        return uint(shares);
    }
    //Looks at pidIn for ownership of any pidOut tokens the user might withdraw
    function subBalance(PoolInfo[] storage _poolInfo, uint _pidIn, uint _pidOut, address _user) internal view returns (int) {
        //user has shares here, pointing to the pool we want?
        int userSharesOut = _poolInfo[_pidIn].user[_user].sharesOut[_pidOut];
        if (userSharesOut == 0) return 0;
        
        //shares that were automatically deposited by pool "In"
        int sharesIn = _poolInfo[_pidIn].sharesIn[_pidIn];
        if (sharesIn == 0) return 0;
        
        int sharesOutTotal = _poolInfo[_pidIn].sharesOut[_pidOut];
        
        return FullMath.mulDiv(userSharesOut, sharesIn, sharesOutTotal);
    }
    
    //user deposits to pid, standard autocompounding
    function add(PoolInfo[] storage _poolInfo, uint _pid, address _user, uint _sharesAdded) internal {
        PoolInfo storage pool = _poolInfo[_pid];

        int sharesAdded = int(_sharesAdded);
        assert(pool.sharesOut[_pid] >= 0);
        assert(pool.sharesIn[_pid] >= 0);
        int sharesOutAdded = pool.sharesIn[_pid] + pool.sharesOut[_pid] == 0 ? sharesAdded :
            FullMath.mulDiv(sharesAdded, pool.sharesOut[_pid], pool.sharesIn[_pid] + pool.sharesOut[_pid]);
            
        int sharesInAdded = sharesAdded - sharesOutAdded;

        pool.sharesTotal += sharesAdded;
        pool.user[_user].shares += sharesOutAdded;
        pool.user[_user].sharesOut[_pid] += sharesOutAdded;

        pool.sharesOut[_pid] += sharesOutAdded;
        pool.sharesIn[_pid] += sharesInAdded;
    }
    
    //user deposits to pidIn, earning to pidOut
    function add(PoolInfo[] storage _poolInfo, uint _pidIn, uint _pidOut, address _user, uint _sharesAdded) internal {
        if (_pidIn == _pidOut) return add(_poolInfo, _pidIn, _user, _sharesAdded);
        
        PoolInfo storage poolIn = _poolInfo[_pidIn];
        PoolInfo storage poolOut = _poolInfo[_pidOut];
        
        int sharesAdded = int(_sharesAdded);
        
        poolIn.user[_user].shares += sharesAdded;
        poolIn.user[_user].sharesOut[_pidOut] += sharesAdded;
        poolIn.sharesTotal += sharesAdded;
        poolIn.sharesOut[_pidOut] += sharesAdded;
        
        assert(poolOut.sharesIn[_pidIn] >= 0);
        assert(poolIn.sharesTotal >= 0);
        int offset = int(FullMath.mulDivRoundingUp(_sharesAdded,uint(poolOut.sharesIn[_pidIn]),uint(poolIn.sharesTotal)));
        
        poolOut.user[_user].shares -= offset;
        poolOut.sharesIn[_pidIn] += offset;
    }
    //pidIn earns shares to pidOut
    function earn(PoolInfo[] storage _poolInfo, uint _pidIn, uint _pidOut, uint _sharesAdded) internal {
        PoolInfo storage poolOut = _poolInfo[_pidOut];
        int sharesAdded = int(_sharesAdded);
        poolOut.sharesTotal += sharesAdded;
        poolOut.sharesIn[_pidIn] += sharesAdded;
    }
    //remove shares from pidIn(earn pidOut), withdrawing from user. Withdraws other shares of same pidIn if necessary to complete withdrawal
    function remove(PoolInfo[] storage _poolInfo, uint _pidIn, uint _pidOut, address _user, uint _sharesRemoved) internal {
        PoolInfo storage poolIn = _poolInfo[_pidIn];
        PoolInfo storage poolOut = _poolInfo[_pidOut];
        
        int sharesRemoved = int(_sharesRemoved);
        int balance = int(balanceOf(_poolInfo, _pidIn, _user));
        require(sharesRemoved <= balance, "libmaxi: insufficient balance");
        //todo
    }
    
    
}