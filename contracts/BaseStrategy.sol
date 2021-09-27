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

abstract contract BaseStrategy is Ownable, ReentrancyGuard, PausableTL {
    using Math for uint256;
    using SafeERC20 for IERC20;

    address immutable public wantAddress;
    address immutable public earnedAddress;

    address immutable public uniRouterAddress;
    address constant public usdAddress = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant public crystlAddress = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    address constant public wNativeAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address public rewardAddress = 0x5386881b46C37CdD30A748f7771CF95D7B213637;
    address public withdrawFeeAddress = 0x5386881b46C37CdD30A748f7771CF95D7B213637;

    uint256 public lastEarnBlock = block.number;
    uint256 public sharesTotal;
    uint256 immutable public tolerance;
    uint256 public burnedAmount;
    bool public feeOnTransferSwapMode; //enabled by strategies dealing with reflect tokens

    address public buyBackAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public controllerFee = 50; // 0.50%
    uint256 public rewardRate = 50; // 0.50%
    uint256 public buyBackRate = 400; // 4%

    uint256 public constant FEE_MAX_TOTAL = 10000;
    uint256 public constant FEE_MAX = 10000; // 100 = 1%

    uint256 public withdrawFeeFactor = 9990; // 0.1% default withdraw fee
    uint256 public constant WITHDRAW_FEE_FACTOR_MAX = 10000;
    uint256 public constant WITHDRAW_FEE_FACTOR_LL = 9900;

    uint256 public slippageFactor = 900; // 10% default slippage tolerance
    uint256 public constant SLIPPAGE_FACTOR_UL = 995;
    uint256 public constant EARN_DUST = 1e12;

    address[] public earnedToWnativePath;
    address[] public earnedToUsdPath;
    address[] public earnedToCrystlPath;
    
    event SetSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawFeeFactor,
        uint256 _slippageFactor
    );

    event SetAddress(
        address rewardAddress,
        address withdrawFeeAddress,
        address buyBackAddress
    );
    
    modifier onlyGov() {
        require(msg.sender == Ownable(owner()).owner(), "!gov");
        _;
    }
    
    constructor(
        address _vaulthealerAddress,
        address _uniRouterAddress,
        address _wantAddress,
        address _earnedAddress,
        uint256 _tolerance,
        address[] memory _earnedToWnativePath,
        address[] memory _earnedToUsdPath,
        address[] memory _earnedToCrystlPath
    ) {
        uniRouterAddress = _uniRouterAddress;
        wantAddress = _wantAddress;
        earnedAddress = _earnedAddress;
        tolerance = _tolerance;
        earnedToWnativePath = _earnedToWnativePath;
        earnedToUsdPath = _earnedToUsdPath;
        earnedToCrystlPath = _earnedToCrystlPath;
        
        //initialize allowance for earned address
        setMaxAllowance(_earnedAddress, _uniRouterAddress);
        
        require(Ownable(_vaulthealerAddress).owner() != address(0), "gov is vaulthealer's owner; can't be zero");
        transferOwnership(_vaulthealerAddress);
    }
    

    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function earn() external virtual;
    function earn(address _to) external virtual;
    function vaultSharesTotal() public virtual view returns (uint256);
    function _resetAllowances() internal virtual;
    function _emergencyVaultWithdraw() internal virtual;
    
    function _beforeDeposit(address _from) internal virtual { }
    function _beforeWithdraw(address _from) internal virtual { }
    function vaultChefAddress() external view returns (address) { return owner(); }
    
    function wantBalance() internal virtual view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this));
    }
    
    function wantLockedTotal() public view returns (uint256) {
        return wantBalance() + vaultSharesTotal();
    }
    
    function deposit(address _userAddress, uint256 _wantAmt) external onlyOwner nonReentrant whenNotPaused returns (uint256) {
        // Call must happen before transfer
        _beforeDeposit(_userAddress);
        uint256 wantLockedBefore = wantLockedTotal();

        IERC20(wantAddress).safeTransferFrom(
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

    function _farm() internal returns (uint256) {
        uint256 wantAmt = wantBalance();
        if (wantAmt == 0) return 0;
        
        uint256 sharesBefore = vaultSharesTotal();
        _vaultDeposit(wantAmt);
        uint256 sharesAfter = vaultSharesTotal();
        
        require(sharesAfter + wantBalance() >= sharesBefore + wantAmt * slippageFactor / 1000,
            "Excessive slippage in vault deposit");
        return sharesAfter - sharesBefore;
    }

    function withdraw(address _userAddress, uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256) {
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

        uint256 sharesRemoved = (_wantAmt * sharesTotal).ceilDiv(wantLockedTotal());
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        require(sharesRemoved >= 1, "Low withdraw - no shares removed");
        sharesTotal -= sharesRemoved;
        
        // Withdraw fee
        uint256 withdrawFee = 
            _wantAmt * 
            (WITHDRAW_FEE_FACTOR_MAX - withdrawFeeFactor) /
            WITHDRAW_FEE_FACTOR_MAX;
        if (withdrawFee > 0) {
            IERC20(wantAddress).safeTransfer(withdrawFeeAddress, withdrawFee);
        }
        
        _wantAmt -= withdrawFee;

        IERC20(wantAddress).safeTransfer(owner(), _wantAmt); //owner is vaulthealer

        return sharesRemoved;
    }

    function distributeFees(uint256 _earnedAmt, address _to) internal returns (uint256) {
        
        uint earnedAmt = _earnedAmt;
        
        // To pay for earn function
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt * controllerFee / FEE_MAX;
            _safeSwap(fee, earnedToWnativePath, _to);
            earnedAmt -= fee;
        }
        //distribute rewards
        if (rewardRate > 0) {
            uint256 fee = _earnedAmt * rewardRate / FEE_MAX;

            if (earnedAddress == crystlAddress) {
                // Earn token is CRYSTL
                IERC20(earnedAddress).safeTransfer(rewardAddress, fee);
            } else {
                _safeSwap(fee, earnedToUsdPath, rewardAddress);
            }

            earnedAmt -= fee;
        }
        //burn crystl
        if (buyBackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * buyBackRate / FEE_MAX;

            _safeSwap(buyBackAmt, earnedToCrystlPath, buyBackAddress);

            earnedAmt -= buyBackAmt;
        }
        
        return earnedAmt;
    }

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

    function setGov(address) external pure {
        revert("Gov is the vaulthealer's owner");
    }
    
    function setSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawFeeFactor,
        uint256 _slippageFactor
    ) external onlyGov {
        require(_controllerFee +_rewardRate + _buyBackRate <= FEE_MAX_TOTAL, "Max fee of 100%");
        require(_withdrawFeeFactor >= WITHDRAW_FEE_FACTOR_LL, "_withdrawFeeFactor too low");
        require(_withdrawFeeFactor <= WITHDRAW_FEE_FACTOR_MAX, "_withdrawFeeFactor too high");
        require(_slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
        controllerFee = _controllerFee;
        rewardRate = _rewardRate;
        buyBackRate = _buyBackRate;
        withdrawFeeFactor = _withdrawFeeFactor;
        slippageFactor = _slippageFactor;

        emit SetSettings(
            _controllerFee,
            _rewardRate,
            _buyBackRate,
            _withdrawFeeFactor,
            _slippageFactor
        );
    }

    function setAddresses(
        address _rewardAddress,
        address _withdrawFeeAddress,
        address _buyBackAddress
    ) external onlyGov {
        require(_withdrawFeeAddress != address(0), "Invalid Withdraw address");
        require(_rewardAddress != address(0), "Invalid reward address");
        require(_buyBackAddress != address(0), "Invalid buyback address");

        rewardAddress = _rewardAddress;
        withdrawFeeAddress = _withdrawFeeAddress;
        buyBackAddress = _buyBackAddress;

        emit SetAddress(_rewardAddress, _withdrawFeeAddress, _buyBackAddress);
    }
    
    function _safeSwap(
        uint256 _amountIn,
        address[] memory _path,
        address _to
    ) internal {
        
        //Handle one-token paths which are simply a transfer
        if (_path.length == 1) {
            if (_path[0] == crystlAddress && _to == buyBackAddress)
                burnedAmount += _amountIn;
            IERC20(_path[0]).safeTransfer(_to, _amountIn);
            return;
        }
        
        uint256[] memory amounts = IUniRouter02(uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length - 1];

        if (_path[_path.length - 1] == crystlAddress && _to == buyBackAddress) {
            burnedAmount += amountOut;
        }

        if (feeOnTransferSwapMode) {
            IUniRouter02(uniRouterAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut * slippageFactor / 1000,
                _path,
                _to,
                block.timestamp + 600
            );
        } else {
            IUniRouter02(uniRouterAddress).swapExactTokensForTokens(
                _amountIn,
                amountOut * slippageFactor / 1000,
                _path,
                _to,
                block.timestamp + 600
            );
        }
    }
    function setMaxAllowance(address token, address spender) internal {
        
        IERC20(token).safeApprove(spender, 0);
        IERC20(token).safeIncreaseAllowance(spender, type(uint256).max);
    }
}