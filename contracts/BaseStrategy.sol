// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

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

abstract contract BaseStrategy is ReentrancyGuard, PausableTL, PathStorage {
    using SafeERC20 for IERC20;

    address constant internal DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant internal CRYSTL = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    address constant internal WNATIVE = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    uint256 constant internal FEE_MAX_TOTAL = 10000;
    uint256 constant internal FEE_MAX = 10000; // 100 = 1%
    uint256 constant internal WITHDRAW_FEE_FACTOR_MAX = 10000;
    uint256 constant internal WITHDRAW_FEE_FACTOR_LL = 9900;
    uint256 constant internal SLIPPAGE_FACTOR_UL = 9950;
    
    uint256 earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    
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
        require(Ownable(_addresses.vaulthealer).owner() != address(0), "gov is vaulthealer's owner; can't be zero");
        
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
    
    function deposit(address _userAddress, uint256 _wantAmt) external onlyVaultHealer nonReentrant whenNotPaused returns (uint256) {
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
        require(sharesAdded >= 1, "Low deposit - no shares added");
        sharesTotal += sharesAdded;

        return sharesAdded;
    }

    function withdraw(address _userAddress, uint256 _wantAmt) external onlyVaultHealer nonReentrant returns (uint256) {
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
        require(sharesRemoved >= 1, "Low withdraw - no shares removed");
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
            "Excessive slippage in vault deposit");
        return sharesAfter - sharesBefore;
    }

    function distributeFees(address _earnedAddress, uint256 _earnedAmt, address _to) internal returns (uint256) {
        return LibBaseStrategy.distributeFees(settings, addresses, _earnedAddress, _earnedAmt, _to, FEE_MAX);
    }

    function _safeSwap(
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) internal {
        burnedAmount += LibBaseStrategy._safeSwap(
            settings,
            addresses,
            _amountIn,
            _tokenA,
            _tokenB,
            _to
        );
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
    //for optimizing liquidity calculations
    function setReflectRate(address _token, uint256 _rate) external onlyGov {
        require(_rate < 10000, "invalid reflect rate");
        reflectRate[_token] = _rate;
    }
    
    //private configuration functions
    function _setSettings(Settings memory _settings) private {
        LibBaseStrategy._setSettings(settings, _settings, FEE_MAX_TOTAL, WITHDRAW_FEE_FACTOR_LL, WITHDRAW_FEE_FACTOR_MAX, SLIPPAGE_FACTOR_UL);
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
    function wantAddress() external view returns (address) { return addresses.want; }
}