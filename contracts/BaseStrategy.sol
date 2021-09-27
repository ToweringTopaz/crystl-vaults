// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./libs/IStrategyCrystl.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";
import "./PausableTL.sol";
import "./PathStorage.sol";

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
    
    uint256 immutable earnedLength; //number of earned tokens;
    uint256 immutable lpTokenLength; //number of underlying tokens (for a LP strategy, usually 2);
    
    struct Addresses {
        address vaulthealer;
        address router;
        address masterchef;
        address rewardFee;
        address withdrawFee;
        address buybackFee;
        address want;
        address[8] earned;
        address[8] lpToken;
    }
    struct Settings {
        uint16 controllerFee;
        uint16 rewardRate;
        uint16 buybackRate;
        uint256 withdrawFeeFactor;
        uint256 slippageFactor;
        uint256 tolerance;
        bool feeOnTransfer;
        uint256 dust; //minimum raw token value considered to be worth swapping or depositing
        uint256 minBlocksBetweenSwaps;
    }
    
    //reward/withdraw: 0x5386881b46C37CdD30A748f7771CF95D7B213637
    //buybackFee: 0x000000000000000000000000000000000000dEaD
    Addresses public addresses;
    
    //standard: ["50", "50", "400", "9990", "9500", "0", "false", "1000000000000", "10"]
    //reflect: ["50", "50", "400", "9990", "9000", "0", "true", "1000000000000", "10"]
    //double reflect: ["50", "50", "400", "9990", "8000", "0", "true", "1000000000000", "10"]
    Settings public settings;
    
    uint256 public lastEarnBlock = block.number;
    uint256 public sharesTotal;
    uint256 public burnedAmount;
    
    event SetSettings(Settings _settings);
    event SetAddress(Addresses _addresses);
    
    modifier onlyGov() {
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
        
        uint earnedAmt = _earnedAmt;
        
        //gas optimization
        uint controllerFee = settings.controllerFee;
        uint rewardRate = settings.rewardRate;
        uint buybackRate = settings.buybackRate;
        
        // To pay for earn function
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt * controllerFee / FEE_MAX;
            _safeSwap(fee, _earnedAddress, WNATIVE, _to);
            earnedAmt -= fee;
        }
        //distribute rewards
        if (rewardRate > 0) {
            uint256 fee = _earnedAmt * rewardRate / FEE_MAX;
            if (_earnedAddress == CRYSTL)
                IERC20(_earnedAddress).safeTransfer(addresses.rewardFee, fee);
            else
                _safeSwap(fee, _earnedAddress, DAI, addresses.rewardFee);

            earnedAmt -= fee;
        }
        //burn crystl
        if (settings.buybackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * buybackRate / FEE_MAX;
            _safeSwap(buyBackAmt, _earnedAddress, CRYSTL, addresses.buybackFee);
            earnedAmt -= buyBackAmt;
        }
        
        return earnedAmt;
    }

    function _safeSwap(
        uint256 _amountIn,
        address _tokenA,
        address _tokenB,
        address _to
    ) internal {
        
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            if (_tokenA == CRYSTL && _to == addresses.buybackFee)
                burnedAmount += _amountIn;
            IERC20(_tokenA).safeTransfer(_to, _amountIn);
            return;
        }
        address[] memory path = getPath(_tokenA, _tokenB);
        
        uint256[] memory amounts = IUniRouter02(addresses.router).getAmountsOut(_amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1];

        if (_tokenB == CRYSTL && _to == addresses.buybackFee) {
            burnedAmount += amountOut;
        }

        if (settings.feeOnTransfer) {
            IUniRouter02(addresses.router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut * settings.slippageFactor / 10000,
                path,
                _to,
                block.timestamp + 600
            );
        } else {
            IUniRouter02(addresses.router).swapExactTokensForTokens(
                _amountIn,
                amountOut * settings.slippageFactor / 10000,
                path,
                _to,
                block.timestamp + 600
            );
        }
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
        for (uint i; i < addresses.earned.length; i++) {
            require(_addresses.earned[i] == addresses.earned[i], "cannot change earned address");
        }
        for (uint i; i < addresses.lpToken.length; i++) {
            require(_addresses.lpToken[i] == addresses.lpToken[i], "cannot change lpToken address");
        }        
        require(_addresses.want == addresses.want, "cannot change want address");
        require(_addresses.masterchef == addresses.masterchef, "cannot change masterchef address");
        require(_addresses.vaulthealer == addresses.vaulthealer, "cannot change masterchef address");
        _setAddresses(_addresses);
    }
    
    //private configuration functions
    function _setSettings(Settings memory _settings) private {
        require(_settings.controllerFee + _settings.rewardRate + _settings.buybackRate <= FEE_MAX_TOTAL, "Max fee of 100%");
        require(_settings.withdrawFeeFactor >= WITHDRAW_FEE_FACTOR_LL, "_withdrawFeeFactor too low");
        require(_settings.withdrawFeeFactor <= WITHDRAW_FEE_FACTOR_MAX, "_withdrawFeeFactor too high");
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
        settings = _settings;
        
        emit SetSettings(_settings);
    }
    
    function _setAddresses(Addresses memory _addresses) private {
        require(_addresses.router != address(0), "Invalid router address");
        IUniRouter02(_addresses.router).factory(); // unirouter will have this function; bad address will revert
        require(_addresses.rewardFee != address(0), "Invalid reward address");
        require(_addresses.withdrawFee != address(0), "Invalid Withdraw address");
        require(_addresses.buybackFee != address(0), "Invalid buyback address");
        addresses = _addresses;

        emit SetAddress(addresses);
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
}