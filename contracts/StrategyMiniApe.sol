// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./libs/IMiniChefV2.sol";
import "./BaseStrategyLP.sol";

contract StrategyMiniApe is BaseStrategyLP {

    uint256 public immutable pid;
    
    constructor(
        Addresses memory _addresses,
        Settings memory _settings,
        address[][] memory _paths,  //need paths for earned/earned2 to each of (wmatic, dai, crystl, token0, token1): 10 total
        uint256 _pid
    ) BaseStrategy(_addresses, _settings, _paths) {
        
        addresses.lpToken[0] = IUniPair(_addresses.want).token0();
        addresses.lpToken[1] = IUniPair(_addresses.want).token1();
        
        pid = _pid;
    }

    function _vaultDeposit(uint256 _amount) internal override {
        IMiniChefV2(addresses.masterchef).deposit(pid, _amount, address(this));
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMiniChefV2(addresses.masterchef).withdraw(pid, _amount, address(this));
    }
    
    function _vaultHarvest() internal override {
        IMiniChefV2(addresses.masterchef).harvest(pid, address(this));
    }
    
    function vaultSharesTotal() public virtual override view returns (uint256) {
        (uint256 amount,) = IMiniChefV2(addresses.masterchef).userInfo(pid, address(this));
        return amount;
    }

    function _emergencyVaultWithdraw() internal override {
        IMiniChefV2(addresses.masterchef).emergencyWithdraw(pid, address(this));
    }
}
