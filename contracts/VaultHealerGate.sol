// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./VaultHealerBase.sol";
import "hardhat/console.sol";


//Handles "gate" functions like deposit/withdraw
abstract contract VaultHealerGate is VaultHealerBase {
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
    PendingDeposit private pendingDeposit;

    function transferData(uint pid, address user) internal view returns (TransferData storage) {
        return _transferData[keccak256(abi.encodePacked(pid, user))]; //what does this do?
    }

    function userTotals(uint256 pid, address user) external view 
        returns (TransferData memory stats, int256 earned) 
    {
        stats = transferData(pid, user);
        
        uint _ts = totalSupply(pid);
        uint staked = _ts == 0 ? 0 : balanceOf(user, pid) * _poolInfo[pid].strat.wantLockedTotal() / _ts;
        earned = int(stats.withdrawals + staked + stats.transfersOut) - int(stats.deposits + stats.transfersIn);
    }
    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt) external  whenNotPaused(_pid) { //nonReentrantPid(_pid)
        _deposit(_pid, _wantAmt, msg.sender);
    }

    // For depositing for other users
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external  whenNotPaused(_pid) { //nonReentrantPid(_pid)
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

            uint256 sharesAdded = pool.strat.deposit(msg.sender, _to, _wantAmt, totalSupply(_pid));

            //we mint tokens for the user via the 1155 contract
            _mint(
                _to,
                _pid, //use the pid of the strategy 
                sharesAdded,
                hex'' //leave this blank for now
            );

        transferData(_pid, _to).deposits += _wantAmt - pendingDeposit.amount;
        delete pendingDeposit;
        }
        emit Deposit(_to, _pid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) external  { //nonReentrantPid(_pid)
        _withdraw(_pid, _wantAmt, msg.sender);
    }

    // For withdrawing to other address
    function withdraw(uint256 _pid, uint256 _wantAmt, address _to) external  { //nonReentrantPid(_pid)
        _withdraw(_pid, _wantAmt, _to);
    }

    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) private {
        //create an instance of pool for the relevant pid, and an instance of user for this pool and the msg.sender
        PoolInfo storage pool = _poolInfo[_pid];

        IStakingPool stakingPool = IStakingPool(pool.strat.stakingPoolAddress());
        //check that user actually has shares in this pid
        uint256 userStakedAndUnstakedShares = balanceOf(_to, _pid) + stakingPool.userStakedAmount(_to); //TODO - ask TT if there's another way to access this?
        require(userStakedAndUnstakedShares > 0, "User has 0 shares");
        
        //unstake here if need be
        if (_wantAmt > balanceOf(_to, _pid) && stakingPool.userStakedAmount(_to) > 0) { //&&stakingPool exists! check that it's not a zero address?
            stakingPool.withdraw(_wantAmt-balanceOf(_to, _pid));
            }

        //call withdraw on the strat itself - returns sharesRemoved and wantAmt (not _wantAmt) - withdraws wantTokens from the vault to the strat
        //TELL THE STRAT HOW MUCH TO WITHDRAW!! - wantAmt, as long as wantAmt is allowed...
        (uint256 sharesRemoved, uint256 wantAmt) = pool.strat.withdraw(msg.sender, _to, _wantAmt, balanceOf(_to, _pid), totalSupply(_pid));

        //burn the tokens equal to sharesRemoved
        _burn(
            _to,
            _pid,
            sharesRemoved
        );

        //updates transferData for this user, so that we are accurately tracking their earn
        transferData(_pid, _msgSender()).withdrawals += wantAmt;
        
        //withdraw fee is implemented here
        if (!paused(_pid) && withdrawFeeRate > 0) { //waive withdrawal fee on paused vaults as there's generally something wrong
            uint feeAmt = wantAmt * withdrawFeeRate / 10000;
            wantAmt -= feeAmt;
            pool.want.safeTransferFrom(address(pool.strat), feeReceiver, feeAmt);
        }
        
        //this call transfers wantTokens from the strat to the user
        pool.want.safeTransferFrom(address(pool.strat), _to, wantAmt);
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    // Withdraw everything from pool for yourself
    function withdrawAll(uint256 _pid) external  { //nonReentrantPid(_pid)
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
                uint pid = ids[i];
                uint underlyingValue = amounts[i] * _poolInfo[pid].strat.wantLockedTotal() / totalSupply(pid);
                transferData(pid, from).transfersOut += underlyingValue;
                transferData(pid, to).transfersIn += underlyingValue;
            }
        }
    }
}
