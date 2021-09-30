// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libs/IMiniChefV2.sol";
import "./BaseStrategyLP.sol";

contract StrategyMiniApe is BaseStrategyLP {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public masterchefAddress; //actually a minichef in this case
    uint256 public pid;
    address public earnedBetaAddress;

    address[] earnedBetaToEarnedPath;

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
        address[] memory _token1ToEarnedPath,
        address[] memory _earnedBetaToEarnedPath
    ) {
        govAddress = msg.sender;
        vaultChefAddress = _configAddress[0];
        masterchefAddress = _configAddress[1];
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
        earnedBetaToEarnedPath = _earnedBetaToEarnedPath;

        transferOwnership(vaultChefAddress);
        
        _resetAllowances();
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
        uint256 earnedBetaAmt = IERC20(earnedBetaAddress).balanceOf(address(this));
        bool earnedSomething;
        
        //converts earnedBeta into Earned
        if (earnedBetaAmt > 0) {
            _safeSwap(
                earnedBetaAmt,
                earnedBetaToEarnedPath,
                address(this)
            );    
        }

        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        if (earnedAmt > 0) {
            earnedSomething = true;
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
        IMiniChefV2(masterchefAddress).deposit(pid, _amount, address(this));
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMiniChefV2(masterchefAddress).withdraw(pid, _amount, address(this));
    }
    
    function _vaultHarvest() internal override {
        IMiniChefV2(masterchefAddress).harvest(pid, address(this));
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = IMiniChefV2(masterchefAddress).userInfo(pid, address(this));
        return amount;
    }
    
    function wantLockedTotal() public override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this))
            .add(vaultSharesTotal());
    }

    function _resetAllowances() internal override {
        IERC20(wantAddress).safeApprove(masterchefAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            masterchefAddress,
            type(uint256).max
        );

        IERC20(earnedAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );
        
        IERC20(earnedBetaAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedBetaAddress).safeIncreaseAllowance(
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
        IMiniChefV2(masterchefAddress).emergencyWithdraw(pid, address(this));
    }

    function _beforeDeposit(address _to) internal override {
        
    }

    function _beforeWithdraw(address _to) internal override {
        
    }
}
