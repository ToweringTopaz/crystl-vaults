// SPDX-License-Identifier: MIT

/*
Join us at PolyCrystal.Finance!
█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/


pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IStrategy.sol";

abstract contract BaseBaseStrategy is Ownable, Pausable, IStrategy {
    using SafeERC20 for IERC20;
    
    address public govAddress = msg.sender;

    uint256 public lastEarnBlock = block.number;
    uint256 public override sharesTotal = 0;

    address public buybackReceiver = 0x0894417Dfc569328617FC25DCD6f0B5F4B0eb323;
    address public depositFeeReceiver = 0x0894417Dfc569328617FC25DCD6f0B5F4B0eb323;

    uint256 public depositFeeRate = 10; // default 0.1% deposit fee
    uint256 public constant DEPOSIT_FEE_MAX = 200; // maximum 2% deposit fee

    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    address public override immutable wantAddress;
    address public immutable vaultHealerAddress;
    address public immutable earnedAddress;

    function isCrystalCore() external override virtual returns (bool) { return false; }
    function isCrystallizer() external override virtual returns (bool) { return false; }

    uint256 public buybackRate = 200;
    uint256 public constant FEE_MAX_TOTAL = 500; // maximum 5% performance fee
    
    uint256 public constant BASIS_POINTS = 10000; // 100 = 1%
    
    uint public panicTimelock;
    uint public constant PANIC_TIMELOCK_DURATION = 129600; // 36 hours
    
    event SetSettings(
        uint256 _depositFee,
        address _depositFeeReceiver,
        uint256 _buybackRate,
        address _buybackReceiver
    );
    
    modifier onlyGov() {
        require(msg.sender == govAddress, "!gov");
        _;
    }

    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function vaultTotal() public virtual override view returns (uint256);
    function wantLockedTotal() public virtual override view returns (uint256);
    function _resetAllowances() internal virtual;
    function _emergencyVaultWithdraw() internal virtual;
    
    constructor (address _wantAddress, address _earnedAddress, address _vaultHealerAddress) {
        wantAddress = _wantAddress;
        earnedAddress = _earnedAddress;
        vaultHealerAddress = _vaultHealerAddress;
    }
    
    
    function deposit(address /*_userAddress*/, uint256 _wantAmt) external override onlyOwner whenNotPaused returns (uint256) {
        if (_wantAmt == 0) return 0;
        
        // Call must happen before transfer
        uint256 wantLockedBefore = wantLockedTotal();
        
        //charge deposit fee, if any
        _wantAmt = depositFee(_wantAmt);
        
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );

        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        uint256 sharesAdded = _farm(_wantAmt);
        if (sharesTotal > 0) {
            sharesAdded = sharesAdded * sharesTotal / wantLockedBefore;
        }
        sharesTotal += sharesAdded;

        return sharesAdded;
    }
    function _farm() internal returns (uint256) {
        return _farm(type(uint).max);
    }

    function _farm(uint wantAmt) internal returns (uint256) {
        
        uint wantBal = IERC20(wantAddress).balanceOf(address(this));
        if (wantAmt > wantBal) wantAmt = wantBal;
        if (wantAmt == 0) return 0;
        
        uint256 sharesBefore = vaultTotal();
        _vaultDeposit(wantAmt);
        uint256 sharesAfter = vaultTotal();
        
        return sharesAfter - sharesBefore;
    }

    function withdraw(address /*_userAddress*/, uint256 _wantAmt) external override onlyOwner returns (uint256) {
        
        require(_wantAmt > 0, "_wantAmt is 0");
        
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantAmt) {
            _vaultWithdraw(_wantAmt - wantAmt);
            wantAmt = IERC20(wantAddress).balanceOf(address(this));
        }

        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        uint256 _wantLockedTotal = wantLockedTotal();
        
        //unreachable, but may not be depending on virtual functions? keeping as a safeguard
        if (_wantAmt > _wantLockedTotal) {
            _wantAmt = _wantLockedTotal;
        }

        uint256 sharesRemoved = _wantAmt * sharesTotal / _wantLockedTotal;

        sharesTotal = sharesTotal - sharesRemoved;
        
        IERC20(wantAddress).safeTransfer(vaultHealerAddress, _wantAmt);

        return sharesRemoved;
    }
    
    function depositFee(uint256 _depositAmt) internal returns (uint256) {
        
        if (depositFeeRate == 0) return _depositAmt;
        
        uint256 feeAmt = _depositAmt * depositFeeRate / BASIS_POINTS;
        
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            depositFeeReceiver,
            feeAmt
        );

        return _depositAmt - feeAmt;
    }

    function buyBack(uint256 _earnedAmt) internal virtual returns (uint256);

    function resetAllowances() external onlyGov {
        _resetAllowances();
    }

    function pause() external onlyGov {
        _pause();
    }

    function unpause() external onlyGov {
        _unpause();
        _resetAllowances();
    }

    function panic() external onlyGov {
        panicTimelock = block.timestamp + PANIC_TIMELOCK_DURATION;
        _pause();
        _emergencyVaultWithdraw();
    }

    function unpanic() external onlyGov {
        require(block.timestamp > panicTimelock, "Can't unpanic until timelock expires");
        _unpause();
        _farm();
    }

    function setGov(address _govAddress) external onlyGov {
        govAddress = _govAddress;
    }
    
    function setSettings(
        uint256 _depositFee,
        address _depositFeeReceiver,
        uint256 _buybackRate,
        address _buybackReceiver
    ) external onlyGov {
        require(_buybackRate <= FEE_MAX_TOTAL, "Max fee of 5%");
        buybackRate = _buybackRate;
        buybackReceiver = _buybackReceiver;
        emit SetSettings(
            _depositFee,
            _depositFeeReceiver,
            _buybackRate,
            _buybackReceiver
        );
    }
}