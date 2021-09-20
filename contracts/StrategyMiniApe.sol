// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./libs/IMiniChefV2.sol";
import "./BaseStrategyLP.sol";

contract StrategyMasterHealer is BaseStrategyLP {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public miniapeAddress;
    uint256 public pid;
    address public earnedBetaAddress;
    
    address[] earnedBetaToWnativePath;
    address[] earnedBetaToUsdcPath;
    address[] earnedBetaToCrystlPath;
    address[] earnedBetaToToken0Path;
    address[] earnedBetaToToken1Path;

    constructor(
        address[6] memory _configAddress, //vaulthealer, miniape, unirouter, want, earned, earnedBeta
        uint256 _pid,
        uint256 _tolerance,
        address[] memory _earnedToWmaticPath,
        address[] memory _earnedToUsdcPath,
        address[] memory _earnedToCrystlPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath
    ) {
        govAddress = msg.sender;
        vaultChefAddress = _configAddress[0];
        miniapeAddress = _configAddress[1];
        uniRouterAddress = _configAddress[2];

        wantAddress = _configAddress[3];
        token0Address = IUniPair(wantAddress).token0();
        token1Address = IUniPair(wantAddress).token1();

        pid = _pid;
        earnedAddress = _configAddress[4];
        earnedBetaAddress = _configAddress[5];
        tolerance = _tolerance;

        earnedToWnativePath = _earnedToWmaticPath;
        earnedToUsdPath = _earnedToUsdcPath;
        earnedToCrystlPath = _earnedToCrystlPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;

        transferOwnership(vaultChefAddress);
        
        _resetAllowances();
    }
    
    function initializeEarnedBeta(
        address[] memory _earnedBetaToWmaticPath,
        address[] memory _earnedBetaToUsdcPath,
        address[] memory _earnedBetaToCrystlPath,
        address[] memory _earnedBetaToToken0Path,
        address[] memory _earnedBetaToToken1Path
    ) external onlyGov {
        require(earnedBetaToWnativePath.length == 0, "already initialized");
        earnedBetaToWnativePath = _earnedBetaToWmaticPath;
        earnedBetaToUsdcPath = _earnedBetaToUsdcPath;
        earnedBetaToCrystlPath = _earnedBetaToCrystlPath;
        earnedBetaToToken0Path = _earnedBetaToToken0Path;
        earnedBetaToToken1Path = _earnedBetaToToken1Path;
    }
    
    
    
    function earn() external override nonReentrant whenNotPaused { 
        _earn(_msgSender());
    }

    function earn(address _to) external override nonReentrant whenNotPaused {
        _earn(_to);
    }

    function _earn(address _to) internal {
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        uint256 earnedBetaAmt = IERC20(earnedBetaAddress).balanceOf(address(this));
        bool earnedSomething = earnedAmt > 0 || earnedBetaAmt > 0;
            
        if (earnedAmt > 0) {
            earnedAmt = distributeFees(earnedAmt, _to);
            earnedAmt = distributeRewards(earnedAmt);
            earnedAmt = buyBack(earnedAmt);
    
            if (earnedAddress != token0Address) {
                // Swap half earned to token0
                _safeSwap(
                    earnedAmt.div(2),
                    earnedToToken0Path,
                    address(this)
                );
            }
    
            if (earnedAddress != token1Address) {
                // Swap half earned to token1
                _safeSwap(
                    earnedAmt.div(2),
                    earnedToToken1Path,
                    address(this)
                );
            }
        }
        
        if (earnedBetaAmt > 0) {
            earnedBetaAmt = distributeFees(earnedBetaAmt, _to);
            earnedBetaAmt = distributeRewards(earnedBetaAmt);
            earnedBetaAmt = buyBack(earnedBetaAmt);
    
            if (earnedBetaAddress != token0Address) {
                // Swap half earned to token0
                _safeSwap(
                    earnedBetaAmt.div(2),
                    earnedBetaToToken0Path,
                    address(this)
                );
            }
    
            if (earnedBetaAddress != token1Address) {
                // Swap half earned to token1
                _safeSwap(
                    earnedBetaAmt.div(2),
                    earnedBetaToToken1Path,
                    address(this)
                );
            }
        }
        if (earnedSomething) {
            // Get want tokens, ie. add liquidity
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            if (token0Amt > 0 && token1Amt > 0) {
                IUniRouter02(uniRouterAddress).addLiquidity(
                    token0Address,
                    token1Address,
                    token0Amt,
                    token1Amt,
                    0,
                    0,
                    address(this),
                    block.timestamp.add(600)
                );
            }
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }
    
    

    function _vaultDeposit(uint256 _amount) internal virtual override {
        IMiniChefV2(miniapeAddress).deposit(pid, _amount, address(this));
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMiniChefV2(miniapeAddress).withdraw(pid, _amount, address(this));
    }
    
    function _vaultHarvest() internal override {
        IMiniChefV2(miniapeAddress).harvest(pid, address(this));
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = IMiniChefV2(miniapeAddress).userInfo(pid, address(this));
        return amount;
    }
    
    function wantLockedTotal() public override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this))
            .add(vaultSharesTotal());
    }

    function _resetAllowances() internal override {
        IERC20(wantAddress).safeApprove(miniapeAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            miniapeAddress,
            type(uint256).max
        );

        IERC20(earnedAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

        IERC20(token0Address).safeApprove(uniRouterAddress, uint256(0));
        IERC20(token0Address).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

        IERC20(token1Address).safeApprove(uniRouterAddress, uint256(0));
        IERC20(token1Address).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

    }
    
    function _emergencyVaultWithdraw() internal override {
        IMiniChefV2(miniapeAddress).emergencyWithdraw(pid, address(this));
    }

    function _beforeDeposit(address _to) internal override {
        
    }

    function _beforeWithdraw(address _to) internal override {
        
    }
}