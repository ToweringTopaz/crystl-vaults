// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Magnetite.sol";

interface IStrategy {
    function wantAddress() external view returns (address); // Want address
    function wantLockedTotal() external view returns (uint256); // Total want tokens managed by strategy
    function paused() external view returns (bool); // Is strategy paused
    function earn(address _to) external; // Main want token compounding function
    function deposit(address _from, address _to, uint256 _wantAmt, uint256 _sharesTotal) external returns (uint256);
    function withdraw(address _from, address _to, uint256 _wantAmt, uint256 _userShares, uint256 _sharesTotal) external returns (uint256 sharesRemoved, uint256 wantAmt);
}

contract VaultHealer is ReentrancyGuard, Magnetite {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 shares; // Shares for standard auto-compound rewards
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        mapping (address => uint256) allowances; //for ERC20 transfers
    }
    struct PoolInfo {
        IERC20 want; // Address of the want token.
        IStrategy strat; // Strategy address that will auto compound want tokens
        uint256 sharesTotal;
        mapping (address => UserInfo) user;
    }
    struct PendingDeposit {
        IERC20 token;
        address from;
        uint256 amount;
    }

    PoolInfo[] internal _poolInfo; // Info of each pool.
    
    //pid+1 for any of our strategies. +1 allows us to distinguish pid 0 from an unauthorized address
    mapping(address => uint) private _strats;
    
    PendingDeposit private pendingDeposit;

    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }
    function poolInfo(uint pid) external view returns (address want, address strat) {
        return (address(_poolInfo[pid].want), address(_poolInfo[pid].strat));
    }
    
    function userInfo(uint _pid, address _user) external view returns (uint256 shares) {
        return _poolInfo[_pid].user[_user].shares;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner nonReentrant {
        require(!isStrat(_strat), "Existing strategy");
        _poolInfo.push();
        PoolInfo storage pool = _poolInfo[_poolInfo.length - 1];
        pool.want = IERC20(IStrategy(_strat).wantAddress());
        pool.strat = IStrategy(_strat);
        
        _strats[_strat] = _poolInfo.length;
        emit AddPool(_strat);
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = pool.user[_user];

        uint256 _sharesTotal = pool.sharesTotal;
        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        if (_sharesTotal == 0) {
            return 0;
        }
        return user.shares * wantLockedTotal / _sharesTotal;
    }
    function userTotals(uint256 _pid, address _user) external view returns (uint256 deposited, uint256 withdrawn, int256 earned) {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = pool.user[_user];
        
        deposited = user.totalDeposits;
        withdrawn = user.totalWithdrawals;
        uint staked = pool.sharesTotal == 0 ? 0 : user.shares * pool.strat.wantLockedTotal() / pool.sharesTotal;
        earned = int(withdrawn + staked) - int(deposited);
    }
    
    //enables sharesTotal function on strategy
    function sharesTotal(address _strat) external view returns (uint) {
        uint pid = findPid(_strat);
        return _poolInfo[pid].sharesTotal;
    }
    function isStrat(address _strat) public view returns (bool) {
        return _strats[_strat] > 0;
    }
    function findPid(address _strat) public view returns (uint) {
        uint pidPlusOne = _strats[_strat];
        require(pidPlusOne > 0, "address is not a strategy on this VaultHealer"); //must revert here for security
        return pidPlusOne - 1;
    }

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt) external nonReentrant {
        _deposit(_pid, _wantAmt, msg.sender);
    }

    // For depositing for other users
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant {
        _deposit(_pid, _wantAmt, _to);
    }

    function _deposit(uint256 _pid, uint256 _wantAmt, address _to) internal {
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
            
            pool.user[_to].totalDeposits = _wantAmt - pendingDeposit.amount;
            delete pendingDeposit;
        }
        emit Deposit(_to, _pid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) external nonReentrant {
        _withdraw(_pid, _wantAmt, msg.sender);
    }

    // For withdrawing to other address
    function withdraw(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant {
        _withdraw(_pid, _wantAmt, _to);
    }

    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) internal {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = pool.user[msg.sender];

        require(user.shares > 0, "user.shares is 0");
        
        (uint256 sharesRemoved, uint256 wantAmt) = pool.strat.withdraw(msg.sender, _to, _wantAmt, user.shares, pool.sharesTotal);
        
        pool.want.transferFrom(address(pool.strat), _to, wantAmt);
        user.totalWithdrawals += wantAmt;
        
        user.shares -= sharesRemoved;
        pool.sharesTotal -= sharesRemoved;

        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    // Withdraw everything from pool for yourself
    function withdrawAll(uint256 _pid) external nonReentrant {
        _withdraw(_pid, type(uint256).max, msg.sender);
    }

    function earnAll() external nonReentrant {
        for (uint256 i; i < _poolInfo.length; i++) {
            try _poolInfo[i].strat.earn(_msgSender()) {}
            catch {}
        }
    }

    function earnSome(uint256[] memory pids) external nonReentrant {
        for (uint256 i; i < pids.length; i++) {
            if (_poolInfo.length >= pids[i]) {
                try _poolInfo[pids[i]].strat.earn(_msgSender()) {}
                catch {}
            }
        }
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
    
    //allows strats to generate paths
    function pathAuth() internal override view returns (bool) {
        return super.pathAuth() || isStrat(msg.sender);
    }
    
    /////////ERC20 functions for shareTokens, enabling boosted vaults
    //The findPid function ensures that the caller is a valid strategy and maps the address to its pid
    function erc20TotalSupply() external view returns (uint256) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        return _poolInfo[pid].sharesTotal;
    }
    function erc20BalanceOf(address account) external view returns (uint256) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        return _poolInfo[pid].user[account].shares;
    }
    function erc20Transfer(address sender, address recipient, uint256 amount) external nonReentrant returns (bool) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        UserInfo storage _sender = _poolInfo[pid].user[sender];
        UserInfo storage _recipient = _poolInfo[pid].user[recipient];
        require(_sender.shares >= amount, "VaultHealer: insufficient balance");
        _sender.shares -= amount;
        _recipient.shares += amount;
        return true;
    }
    function erc20Allowance(address owner, address spender) external view returns (uint256) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        return _poolInfo[pid].user[owner].allowances[spender];
    }
    function erc20Approve(address owner, address spender, uint256 amount) external nonReentrant returns (bool) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        _poolInfo[pid].user[owner].allowances[spender] = amount;
        return true;
    }
    function erc20TransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external nonReentrant returns (bool) {
        uint pid = findPid(msg.sender); //authenticates as strategy
        UserInfo storage _sender = _poolInfo[pid].user[sender];
        UserInfo storage _recipient = _poolInfo[pid].user[recipient];
        require(_sender.shares >= amount, "VaultHealer: insufficient balance");
        require(_sender.allowances[recipient] >= amount, "VaultHealer: insufficient allowance");
        _sender.allowances[recipient] -= amount;
        _sender.shares -= amount;
        _recipient.shares += amount;
        return true;
    }
    
}
