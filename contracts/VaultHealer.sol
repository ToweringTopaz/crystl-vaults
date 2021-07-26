// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;


import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IStrategy.sol";
import "./Operators.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract VaultHealer is ReentrancyGuard, Operators {
    using SafeERC20 for IERC20;
    
    mapping(address => IERC20) public strategyWant; // Want token for a given strategy address
    mapping(uint256 => address) public strategyAddress;
    mapping(uint256 => mapping(address => uint256)) internal userShares; // For each strategy, shares for each user that stakes LP tokens.
    mapping(uint256 => bool) public compoundDisabled;

    uint24 public numStrategies;
    
    //0: compound by anyone; 1: EOA only; 2: restricted to operators
    uint8 public compoundLock;
    bool public autocompoundOn = true;
    uint16 public compoundDivisor = 1;

    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetCompoundMode(bool automatic, uint16 divisor, uint8 locked);
    event CompoundError(uint, bytes);
    
    /**
     * @dev Add a new strategy to the vaults. Can only be called by the owner.
     */
    function addStrategy(address strat) public virtual onlyOwner nonReentrant {
        require(Address.isContract(strat), "strategy isn't a contract!");
        
        uint _numStrategies = numStrategies;
        
        for (uint i; i < _numStrategies; i++) {
            require(strategyAddress[i] != strat, "Existing strategy");
        }
        
        strategyAddress[_numStrategies] = strat;
        strategyWant[strat] = IERC20(IStrategy(strat).wantAddress());

        resetSingleAllowance(_numStrategies); //authorize token transfers for the new strategy
        numStrategies++; // increment the number of strategies here

        emit AddPool(strat);
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _sid, address _user) public view returns (uint256) {
        
        IStrategy strat = IStrategy(strategyAddress[_sid]);

        uint256 sharesTotal = strat.sharesTotal();
        uint256 wantLockedTotal = strat.wantLockedTotal();
        
        if (sharesTotal == 0) return 0;
        return userShares[_sid][_user] * wantLockedTotal / sharesTotal;
    }

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _sid, uint256 _wantAmt) external nonReentrant {
        require (_sid < numStrategies, "pool doesn't exist");
        autoCompound(_sid);
        _deposit(_sid, _wantAmt, msg.sender);
    }

    // For unique contract calls
    function deposit(uint256 _sid, uint256 _wantAmt, address _to) external nonReentrant onlyOperator {
        _deposit(_sid, _wantAmt, _to);
    }
    
    function _deposit(uint256 _sid, uint256 _wantAmt, address _to) internal virtual {
        address strat = strategyAddress[_sid];

        if (_wantAmt > 0) {
            strategyWant[strat].safeTransferFrom(msg.sender, address(this), _wantAmt);

            uint256 sharesAdded = IStrategy(strat).deposit(_to, _wantAmt);
            userShares[_sid][_to] += sharesAdded;
        }
        emit Deposit(_to, _sid, _wantAmt);
    }

    function withdraw(uint256 _sid, uint256 _wantAmt) external nonReentrant {
        autoCompound(_sid);
        _withdraw(_sid, _wantAmt, msg.sender);
    }

    // For unique contract calls
    function withdraw(uint256 _sid, uint256 _wantAmt, address _to) external nonReentrant onlyOperator {
        _withdraw(_sid, _wantAmt, _to);
    }

    function _withdraw(uint256 _sid, uint256 _wantAmt, address _to) internal virtual {
        require (_sid < numStrategies, "pool doesn't exist");
        
        address strat = strategyAddress[_sid];
        uint256 _shares = userShares[_sid][msg.sender];
        require(_shares > 0, "user.shares is 0");
        
        uint256 wantLockedTotal = IStrategy(strat).wantLockedTotal();
        
        uint256 sharesTotal = IStrategy(strat).sharesTotal();
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw want tokens
        uint256 amount = _shares * wantLockedTotal / sharesTotal;
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved = IStrategy(strat).withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > _shares) {
                userShares[_sid][msg.sender] = 0;
            } else {
               userShares[_sid][msg.sender] = _shares - sharesRemoved;
            }

            uint256 wantBal = strategyWant[strat].balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            strategyWant[strat].safeTransfer(_to, _wantAmt);
        }
        emit Withdraw(msg.sender, _sid, _wantAmt);
    }

    // Withdraw everything from pool for yourself
    function withdrawAll(uint256 _sid) external nonReentrant {
        autoCompound(_sid);
        _withdraw(_sid, type(uint256).max, msg.sender);
    }

    function resetAllowances() external onlyOwner {
        uint _numStrategies = numStrategies;
        for (uint i; i < _numStrategies; i++) {
            address strat = strategyAddress[i];
            strategyWant[strat].safeApprove(strat, uint256(0));
            strategyWant[strat].safeIncreaseAllowance(strat, type(uint256).max);
        }
    }

    function resetSingleAllowance(uint256 _sid) public onlyOwner {
        address strat = strategyAddress[_sid];
        strategyWant[strat].safeApprove(strat, uint256(0));
        strategyWant[strat].safeIncreaseAllowance(strat, type(uint256).max);
    }
    

    function setCompoundMode(uint8 lock, bool autoC, uint16 divisor) external onlyOwner {
        compoundLock = lock;
        autocompoundOn = autoC;
        compoundDivisor = divisor;
        emit SetCompoundMode(autoC,divisor,lock);
    }

    function compoundAll(uint sid) external {
        require(compoundLock == 0 || operators[msg.sender] || (compoundLock == 1 && msg.sender == tx.origin), "Compounding is restricted");
            _compoundAll(sid);
    }
    
    //disables compounding for any one strategy
    function disableCompounding(uint strat, bool disabled) external onlyOwner {
        compoundDisabled[strat] = disabled;
    }
    
    //In the event of high gas costs due to a large number of strategy contracts, this will set autocompounding to only affect 
    // some fraction of the pools: 1/2, 1/3, 1/4, 1/5... This will include the selected pool, so it will always compound before deposit/withdraw
    function setCompoundDivisor(uint divisor) external onlyOwner {
        require(divisor != 0, "can't configure to divide by zero");
        require(divisor <= numStrategies, "can't be more than number of strategies");
        compoundDivisor = uint16(divisor);
    }
    
    function autoCompound(uint sid) internal {
        if (autocompoundOn && (compoundLock == 0 || operators[msg.sender] || (compoundLock == 1 && msg.sender == tx.origin)))
            _compoundAll(sid);
    }
    
    function _compoundAll(uint sid) internal virtual {
        uint _numStrategies = numStrategies;
        uint divisor = compoundDivisor;
        uint modulus = sid % divisor;
        
        for (uint i = 1; i < _numStrategies; i++) {
            if (i % divisor != modulus || compoundDisabled[i]) continue;
            
            address strat = strategyAddress[i];
            
            //If something goes wrong with one strategy compounding, let's not break deposit and withdraw
            try IStrategy(strat).earn() returns (uint) {}
            catch (bytes memory reason) {
                emit CompoundError(i, reason);
            }
        }
    }
    
}