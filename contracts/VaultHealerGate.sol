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
        // console.log("made it into the deposit function in VH");
        PoolInfo storage pool = _poolInfo[_pid];

        require(address(pool.strat) != address(0), "That strategy does not exist");

        if (_wantAmt > 0) {
            pendingDeposit = PendingDeposit({ //todo: understand better what this does
                token: pool.want,
                from: msg.sender,
                amount: _wantAmt
            });
            
            uint256 sharesAdded = pool.strat.deposit(msg.sender, _to, _wantAmt, totalSupply(_pid));
            // console.log("sharesAdded");
            //we mint tokens for the user via the 1155 contract
            _mint(
                _to,
                _pid, //use the pid of the strategy 
                sharesAdded,
                hex'' //leave this blank for now
            );
            // console.log("made it past mint");
        //update the user's data for earn tracking purposes
        transferData(_pid, _to).deposits += _wantAmt - pendingDeposit.amount; //todo: should this go here or higher up? above the strat.deposit?
        
        pool.rewardDebt[_to] = balanceOf(_to, _pid)  * pool.strat.accRewardTokensPerShare() / 1e30; //todo: should this go here or higher up? above the strat.deposit?

        // console.log("made it past transferData");
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
        uint256 userUnboostedWant = balanceOf(_to, _pid) * pool.strat.wantLockedTotal() / totalSupply(_pid);
        uint256 userBoostedWant;
        if (address(stakingPool) != address(0)) {
            userBoostedWant = stakingPool.userStakedAmount(_to) * pool.strat.wantLockedTotal() / totalSupply(_pid);
            } else userBoostedWant = 0;

        require(userUnboostedWant + userBoostedWant > 0, "User has 0 shares");
        
        //unstake here if need be
        if (_wantAmt > userUnboostedWant && userBoostedWant > 0) { //&&stakingPool exists! check that it's not a zero address?
            stakingPool.withdraw((_wantAmt-userUnboostedWant)*totalSupply(_pid) / pool.strat.wantLockedTotal(), _to);
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
        if (!paused(_pid) && defaultFees.withdraw.rate > 0) { //waive withdrawal fee on paused vaults as there's generally something wrong
            uint feeAmt = wantAmt * defaultFees.withdraw.rate / 10000;
            wantAmt -= feeAmt;
            pool.want.safeTransferFrom(address(pool.strat), defaultFees.withdraw.receiver, feeAmt);
        }
        
        //this call transfers wantTokens from the strat to the user
        pool.want.safeTransferFrom(address(pool.strat), _to, wantAmt);

        pool.rewardDebt[_to] = balanceOf(_to, _pid) * pool.strat.accRewardTokensPerShare() / 1e30; //todo: should this go here or higher up? above the strat.deposit?

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
        console.log(_to);
        console.log(pendingDeposit.from);
        pendingDeposit.token.safeTransferFrom(
            pendingDeposit.from,
            _to,
            _amount
        );
        // console.log("made it to the end");
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
