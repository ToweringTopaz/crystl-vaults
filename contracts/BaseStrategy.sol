// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./libs/IStrategyCrystl.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";
import "./PausableTL.sol";
import "./PathStorage.sol";

import "./libs/StratStructs.sol";
import "./libs/LibBaseStrategy.sol";

import "hardhat/console.sol";

abstract contract BaseStrategy is ReentrancyGuard, PausableTL, PathStorage {
    using SafeERC20 for IERC20;

    uint256 earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    bool constant _DEBUG_ = true;
    
    Addresses public addresses;
    Settings public settings;
    
    uint256 public lastEarnBlock = block.number;
    uint256 public lastGainBlock; //last time earn() produced anything
    uint256 public sharesTotal;
    uint256 public burnedAmount;
    
    mapping(address => uint256) public reflectRate;
    
    modifier onlyGov() virtual {
        require(msg.sender == Ownable(addresses.vaulthealer).owner(), "!gov");
        _;
    }
    modifier onlyVaultHealer() {
        require(msg.sender == addresses.vaulthealer, "!vaulthealer");
        _;
    }

    constructor(
        Addresses memory _addresses,
        Settings memory _settings,
        address[][] memory _paths
    ) {
        require(Ownable(_addresses.vaulthealer).owner() != address(0), "VH must have owner"); //because gov is the vaulthealer's owner
        
        _setAddresses(_addresses);
        _setSettings(_settings);
        
        uint i;
        for (i = 0; i < _paths.length; i++) {
            _setPath(_paths[i]);
        }
        for (i = 0; i < _addresses.lpToken.length && _addresses.lpToken[i] != address(0); i++) {}
        earnedLength = i;
        for (i = 0; i < _addresses.lpToken.length && _addresses.lpToken[i] != address(0); i++) {}
        lpTokenLength = i;
        
        _resetAllowances();

    }
    
    //depend on masterchef
    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function _earn(address _to) internal virtual;
    function vaultSharesTotal() public virtual view returns (uint256);
    function _emergencyVaultWithdraw() internal virtual;
    
    //currently unused
    function _beforeDeposit(address _from) internal virtual { }
    function _beforeWithdraw(address _from) internal virtual { }
    
    //simple balance functions
    function wantBalance() internal view returns (uint256) {
        return IERC20(addresses.want).balanceOf(address(this));
    }
    
    function wantLockedTotal() public view returns (uint256) {
        return wantBalance() + vaultSharesTotal();
    }
    
    function earn() external nonReentrant { 
        _earn(_msgSender());
    }
    function earn(address _to) external nonReentrant {
        _earn(_to);
    }
    
    function deposit(address _userAddress, uint256 _wantAmt) external virtual onlyVaultHealer nonReentrant whenNotPaused returns (uint256) {
        // Call must happen before transfer
        _beforeDeposit(_userAddress);
        uint256 wantLockedBefore = wantLockedTotal();

        IERC20(addresses.want).safeTransferFrom(
            msg.sender,
            address(this),
            _wantAmt
        );

        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        uint256 sharesAdded = _farm();
        if (sharesTotal > 0) {
            sharesAdded = sharesAdded * sharesTotal / wantLockedBefore;
        }
        require(sharesAdded >= 1, "deposit: no shares added");
        sharesTotal += sharesAdded;

        return sharesAdded;
    }

    function withdraw(address _userAddress, uint256 _wantAmt) external virtual onlyVaultHealer nonReentrant returns (uint256) {
        require(_wantAmt > 0, "_wantAmt is 0");
        
        _beforeWithdraw(_userAddress);
        uint256 wantAmt = wantBalance();
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantAmt) {
            _vaultWithdraw(_wantAmt - wantAmt);
            wantAmt = wantBalance();
            
            if (_wantAmt > wantAmt) {
                _wantAmt = wantAmt;
            }
        }

        uint256 sharesRemoved = Math.ceilDiv(_wantAmt * sharesTotal, wantLockedTotal());
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        require(sharesRemoved >= 1, "withdraw: no shares removed");
        sharesTotal -= sharesRemoved;
        
        // Withdraw fee
        uint256 withdrawFee = 
            _wantAmt * 
            (WITHDRAW_FEE_FACTOR_MAX - settings.withdrawFeeFactor) /
            WITHDRAW_FEE_FACTOR_MAX;
        if (withdrawFee > 0) {
            IERC20(addresses.want).safeTransfer(addresses.withdrawFee, withdrawFee);
        }
        
        _wantAmt -= withdrawFee;

        IERC20(addresses.want).safeTransfer(addresses.vaulthealer, _wantAmt);

        return sharesRemoved;
    }

    function _farm() internal returns (uint256) {
        uint256 wantAmt = wantBalance();
        if (wantAmt == 0) return 0;
        
        uint256 sharesBefore = vaultSharesTotal();
        _allowVaultDeposit(wantAmt);
        _vaultDeposit(wantAmt);
        uint256 sharesAfter = vaultSharesTotal();
        
        require(sharesAfter + wantBalance() >= sharesBefore + wantAmt * settings.slippageFactor / 10000,
            "High vault deposit slippage");
        return sharesAfter - sharesBefore;
    }

    function distributeFees(address _earnedAddress, uint256 _earnedAmt, address _to) internal returns (uint256) {
        return LibBaseStrategy.distributeFees(settings, addresses, _earnedAddress, _earnedAmt, _to);
    }

    function _safeSwap(
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) internal {
        console.log("_safeSwap: amountIn: %s to: %s path: %s", _amountIn, _to, string(abi.encode(getPath(_tokenA, _tokenB))));
        burnedAmount += LibBaseStrategy._safeSwap(
            settings,
            addresses,
            _amountIn,
            _tokenA,
            _tokenB,
            _to
        );
        console.log("burned: %s", burnedAmount);
    }

    //Admin functions
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
        _pause();
        _emergencyVaultWithdraw();
    }
    function unpanic() external onlyGov {
        _unpause();
        _farm();
    }
    function setPath(address[] calldata _path) external onlyGov {
        _setPath(_path);
    }
    function setSettings(Settings calldata _settings) external onlyGov {
        _setSettings(_settings);
    }
    function setAddresses(Addresses calldata _addresses) external onlyGov {
        LibBaseStrategy.setAddresses(addresses, _addresses);
    }
    
    //private configuration functions
    function _setSettings(Settings memory _settings) private {
        LibBaseStrategy._setSettings(settings, _settings);
    }
    
    function _setAddresses(Addresses memory _addresses) private {
        LibBaseStrategy._setAddresses(addresses, _addresses);
    }
    function _setMaxAllowance(address token, address spender) private {
        IERC20(token).safeApprove(spender, 0);
        IERC20(token).safeIncreaseAllowance(spender, type(uint256).max);
    }
    function _setZeroAllowance(address token, address spender) private {
        IERC20(token).safeApprove(spender, 0);
    }
    function _resetAllowances() private {
        _setZeroAllowance(addresses.want, addresses.masterchef);
        for (uint i; i < addresses.earned.length; i++) {
            if (addresses.earned[i] != address(0))
                _setMaxAllowance(addresses.earned[i], addresses.router);
        }
    }
    function _allowVaultDeposit(uint256 _amount) private {
        IERC20(addresses.want).safeIncreaseAllowance(addresses.masterchef, _amount);
    }
    //deprecated; for front-end
    function buyBackRate() external view returns (uint) { return settings.buybackRate; }
    function tolerance() external view returns (uint) { return settings.tolerance; }
    function vaultChefAddress() external view returns (address) { return addresses.vaulthealer; }
    function setGov(address) external pure {
        revert("Gov is the vaulthealer's owner");
    }
    //required by vaulthealer
    function wantAddress() external view returns (address) { return addresses.want; }
}