// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./VaultHealer.sol";
import "./libraries/MoreMath.sol";
import "./MonolithERC20.sol";

contract VaultMonolith is VaultHealer, MonolithERC20 {
    using SafeERC20 for IERC20;

    address public constant CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    mapping(address => bool) public isCrystallizer;
    mapping(uint256 => uint256) internal crystallizerSID; // to look up the strategy ID for each crystallizer
    
    // user or crystallizer's shares in the crystal core vault; can be negative as portions are reallocated if a user deposits or withdraws
    mapping(address => int) crystalCoreShares;
    
    IStrategy crystalCore;
    uint internal numCrystallizers;

    function addStrategy(address strat) public override onlyOwner nonReentrant {
        uint _numStrategies = numStrategies;
        
        if (_numStrategies == 0) {
            require(IStrategy(strat).isCrystalCore() == true, "First strategy must be crystalcore");
            crystalCore = IStrategy(strat);
        } else {
            require(IStrategy(strat).isCrystalCore() == false, "Crystalcore can only be first strategy");
            
            //enable special behavior if it's a crystallizer
            if (IStrategy(strat).isCrystallizer()) {
                isCrystallizer[address(strat)] = true;
                crystallizerSID[numCrystallizers] = _numStrategies;
                numCrystallizers++;
            }
        }
        
        VaultHealer.addStrategy(strat);
    }
    
    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _sid, address _user) public view override returns (uint256) {
        
        if (_sid == 0) {
            int shares = crystlShares(_user);
            if (shares <= 0) return 0;
            
            return uint(shares) * crystalCore.wantLockedTotal() / crystalCore.sharesTotal();
        }
        
        return VaultHealer.stakedWantTokens(_sid, _user);
    }

    function getUserShares(uint256 _sid, address _user) public override view returns (uint256) {
        require(_sid != 0);
        return VaultHealer.getUserShares(_sid, _user);
    }
    function setUserShares(uint256 _sid, address _user, uint newShares) internal override {
        require(_sid != 0);
        return VaultHealer.setUserShares(_sid, _user, newShares);
    }

    //returns a user's share of the crystal core vault
    function crystlShares(address _user) public view returns (int shares) {

        if (isCrystallizer[_user]) return 0;

        shares = crystalCoreShares[_user];
        
        //Add the user's share of each crystallizer's share of the crystal core vault. No need to do this if the user is a crystallizer, as
        //crystallizers won't have shares in anything except the core.
        for (uint i; i < numCrystallizers; i++) {
            uint _sid = crystallizerSID[i];
            uint userLizerShares = getUserShares(_sid, _user); //user's share of the crystallizer
            if (userLizerShares == 0) continue;
            
            address crystallizer = strategyAddress[_sid];
            
            uint lizerSharesTotal = IStrategy(crystallizer).sharesTotal(); //total shares of the crystallizer vault
            int lizerCoreShares = crystalCoreShares[crystallizer]; // crystallizer's share of the core vault

            shares += lizerCoreShares * int(userLizerShares) / int(lizerSharesTotal);
        }
    }
  
    function _deposit(uint256 _sid, uint256 _wantAmt, address _to) internal override {

        if (_wantAmt > 0) {
            address strat = strategyAddress[_sid];
            strategyWant[strat].safeTransferFrom(msg.sender, address(this), _wantAmt);

            //Adding shares to a crystallizer will reduce the share of the crystal core for everyone else, and
            //credit unearned shares to the depositor. We must compensate for this here
            if (isCrystallizer[address(strat)]) {
                uint lizerSharesTotal = IStrategy(strat).sharesTotal(); // shares (non-crystl) for the crystallizer
                int lizerCoreShares = crystalCoreShares[strat]; // crystal core shares held by the crystallizer
        
                uint256 sharesAdded = IStrategy(strat).deposit(_to, _wantAmt); // do the deposit
                
                //old/new == old/new; vault gets +shares, depositor gets -shares but it all evens out
                if (lizerSharesTotal > 0) {
                    int crystalShareOffset = MoreMath.mulDiv(lizerCoreShares, lizerSharesTotal + sharesAdded, lizerSharesTotal) - lizerCoreShares;
                    crystalCoreShares[strat] += crystalShareOffset;
                    crystalCoreShares[_to] -= crystalShareOffset;
                } 
            } else if (_sid == 0) {
                uint256 sharesAdded = IStrategy(strat).deposit(_to, _wantAmt);
                crystalCoreShares[_to] += int(sharesAdded);
                emit Transfer(address(0), _to, _wantAmt);
            } else {
                uint256 sharesAdded = IStrategy(strat).deposit(_to, _wantAmt);
                setUserShares(_sid, _to, getUserShares(_sid, _to) + sharesAdded);
            }
        }
        emit Deposit(_to, _sid, _wantAmt);
    }

    function _withdraw(uint256 _sid, uint256 _wantAmt, address _to) internal override {
        require (_sid < numStrategies, "pool doesn't exist");
        address strat = strategyAddress[_sid];
        uint256 sharesTotal = IStrategy(strat).sharesTotal();
        require(sharesTotal > 0, "sharesTotal is 0");
        uint256 _shares;
        
        if (_sid == 0) {
            int256 _cshares = crystlShares(msg.sender);
            require(_cshares > 0, "user.shares is 0");
            _shares = uint(_cshares);
        } else {
            _shares = getUserShares(_sid, msg.sender);
            require(_shares > 0, "user.shares is 0");
        }
        
        uint256 wantLockedTotal = IStrategy(strat).wantLockedTotal();
        
        // Withdraw want tokens
        uint256 amount = _shares * wantLockedTotal / sharesTotal;
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved = IStrategy(strat).withdraw(msg.sender, _wantAmt);

            if (_sid == 0) {
                emit Transfer(msg.sender, address(0), _wantAmt);
                crystalCoreShares[msg.sender] -= int(sharesRemoved);
            } else {
                if (sharesRemoved > _shares) sharesRemoved = _shares;       //for crystallizer, remove more or fewer shares? difference likely negligible
                setUserShares(_sid, msg.sender, _shares - sharesRemoved);
            }

            if (isCrystallizer[address(strat)]) {
                //old/new == old/new; vault gets -shares, depositor gets +shares but it all evens out
                if (sharesTotal > 0) {
                    int lizerCoreShares = crystalCoreShares[strat]; // crystal core shares held by the crystallizer
                    
                    int crystalShareOffset = lizerCoreShares - MoreMath.mulDiv(_shares - sharesRemoved, lizerCoreShares, sharesTotal);
                    crystalCoreShares[strat] -= crystalShareOffset;
                    crystalCoreShares[_to] += crystalShareOffset;
                } 
            }

            uint256 wantBal = strategyWant[strat].balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            strategyWant[strat].safeTransfer(_to, _wantAmt);
        }
        emit Withdraw(msg.sender, _sid, _wantAmt);
    }
    
    function _compoundAll(uint sid) internal override {
        uint _numStrategies = numStrategies;
        uint divisor = compoundDivisor;
        uint modulus = sid % divisor;
        
        if (!compoundDisabled[0]) IStrategy(strategyAddress[0]).earn();
        
        for (uint i = 1; i < _numStrategies; i++) {
            if (i % divisor != modulus || compoundDisabled[i]) continue;
            
            address strat = strategyAddress[i];
            
            //If something goes wrong with one strategy compounding, let's not break deposit and withdraw
            try IStrategy(strat).earn() returns (uint crystlHarvest) {
                if (crystlHarvest > 0) crystlDeposit(crystlHarvest, strat);

            }
            catch (bytes memory reason) {
                emit CompoundError(i, reason);
            }
        }
    }
    
    //like deposit, but this deposits crystl on behalf of crystallizer strategies
    function crystlDeposit(uint256 _wantAmt, address strat) internal {
        int sharesAdded = int(crystalCore.deposit(strat, _wantAmt));
        crystalCoreShares[strat] += sharesAdded;

        emit Deposit(strat, 0, _wantAmt);
    }

    ////
    //// ERC20 implementation below
    ////
        //transfer fee is for account-to-account transfer of shares so the standard deposit fee can't be avoided, default 0.1%, max 2%
    constructor(uint _transferFeeRate, address _transferFeeReceiver)
        MonolithERC20(transferFeeRate, _transferFeeReceiver) {
        transferFeeRate = _transferFeeRate;
        transferFeeReceiver = _transferFeeReceiver;
    }
    
    function totalSupply() public override view returns (uint) {
        return crystalCore.wantLockedTotal();
    }
    
    function balanceOf(address account) public view override returns (uint) {
        IStrategy _crystalCore = crystalCore;
        uint totalShares = _crystalCore.sharesTotal();
        int _shares = crystlShares(account);
        if (_shares <= 0 || totalShares == 0) return 0;
        
        return uint(_shares) * _crystalCore.wantLockedTotal() / totalShares;
    }
    
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        
        IStrategy _crystalCore = crystalCore;
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0) && recipient != address(this) && recipient != address(_crystalCore), "ERC20: transfer to invalid address");

        int shareBalance = crystlShares(sender);
        uint amountInShares = amount * _crystalCore.sharesTotal() / _crystalCore.wantLockedTotal();
        require(shareBalance >= 0 && amountInShares <= uint(shareBalance), "ERC20: transfer amount exceeds balance");

        crystalCoreShares[sender] -= int(amountInShares);
        int fee = int(transferFeeRate*amountInShares / BASIS_POINTS);
        
        crystalCoreShares[transferFeeReceiver] += fee;
        crystalCoreShares[recipient] += int(amountInShares) - fee;

        emit Transfer(sender, recipient, amount);
    }
}
    

    
