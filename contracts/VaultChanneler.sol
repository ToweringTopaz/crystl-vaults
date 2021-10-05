// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VaultHealer.sol";

contract VaultChanneler is VaultHealer {
    using Boolean256 for bool256;

/*

*/

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user) external override view returns (uint256) {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = pool.user[_user];

        uint256 _sharesTotal = pool.sharesTotal;
        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        uint256 xTokensTotal = pool.xTokensTotal;
        if (_sharesTotal == 0) {
            return 0;
        }
        return user.shares * wantLockedTotal / _sharesTotal;
    }
}