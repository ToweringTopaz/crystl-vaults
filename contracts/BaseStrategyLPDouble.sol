// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./BaseStrategy.sol";

abstract contract BaseStrategyLPDouble is BaseStrategy {
    using SafeERC20 for IERC20;
    
    address public token0Address;
    address public token1Address;

    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    
    address public earned2Address;
    
    address[] public earned2ToWnativePath;
    address[] public earned2ToUsdPath;
    address[] public earned2ToCrystlPath;
    address[] public earned2ToToken0Path;
    address[] public earned2ToToken1Path;
    
    function earn() external override nonReentrant { 
        _earn(_msgSender());
    }

    function earn(address _to) external override nonReentrant {
        _earn(_to);
    }

    function _earn(address _to) internal {
        
        //No good reason to execute _earn twice in a block
        //Vault must not _earn() while paused!
        if (block.number == lastEarnBlock || paused()) return;
        
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        if (earnedAmt > EARN_DUST) {
            earnedAmt = distributeFees(earnedAmt, _to);
    
            // Swap half earned to token0
            _safeSwap(earnedAmt / 2, earnedToToken0Path, wantAddress);
    
            // Swap half earned to token1
            _safeSwap(earnedAmt / 2, earnedToToken1Path, wantAddress);
        }
        //Do second earned token
        uint256 earned2Amt = IERC20(earned2Address).balanceOf(address(this));

        if (earned2Amt > EARN_DUST) {
            earned2Amt = distributeFeesE2(earned2Amt, _to);
            
            // Swap half earned to token0
            _safeSwap(earned2Amt / 2, earned2ToToken0Path, wantAddress);
    
            // Swap half earned to token1
            _safeSwap(earned2Amt / 2, earned2ToToken1Path, wantAddress);
        }
        if (earnedAmt > EARN_DUST || earned2Amt > EARN_DUST) {
            // Get want tokens, ie. add liquidity
            IUniPair(wantAddress).mint(address(this));
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }
    function distributeFeesE2(uint256 _earned2Amt, address _to) internal returns (uint256) {
        
        uint earned2Amt = _earned2Amt;
        
        // To pay for earn function
        if (controllerFee > 0) {
            uint256 fee = _earned2Amt * controllerFee / FEE_MAX;
            _safeSwap(fee, earned2ToWnativePath, _to);
            earned2Amt -= fee;
        }
        //distribute rewards
        if (rewardRate > 0) {
            uint256 fee = _earned2Amt * rewardRate / FEE_MAX;

            if (earned2Address == crystlAddress) {
                // Earn token is CRYSTL
                IERC20(earned2Address).safeTransfer(rewardAddress, fee);
            } else {
                _safeSwap(fee, earned2ToUsdPath, rewardAddress);
            }

            earned2Amt -= fee;
        }
        //burn crystl
        if (buyBackRate > 0) {
            uint256 buyBackAmt = _earned2Amt * buyBackRate / FEE_MAX;

            _safeSwap(buyBackAmt, earned2ToCrystlPath, buyBackAddress);

            earned2Amt -= buyBackAmt;
        }
        
        return earned2Amt;
    }
}