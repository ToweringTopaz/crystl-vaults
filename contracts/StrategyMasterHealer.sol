// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./libs/IMasterchef.sol";
import "./BaseStrategyLP.sol";

contract StrategyMasterHealer is BaseStrategyLP {

    uint256 immutable public pid;

    constructor(
        Addresses memory _addresses,
        Settings memory _settings,
        address[][] memory _paths,  //need paths for earned to each of (wmatic, dai, crystl, token0, token1): 5 total
        uint256 _pid
    ) BaseStrategy(_addresses, _settings, _paths) {
        
        addresses.lpToken[0] = IUniPair(_addresses.want).token0();
        addresses.lpToken[1] = IUniPair(_addresses.want).token1();
        
        pid = _pid;
    }

    function _vaultDeposit(uint256 _amount) internal virtual override {
        IMasterchef(addresses.masterchef).deposit(pid, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal virtual override {
        IMasterchef(addresses.masterchef).withdraw(pid, _amount);
    }
    
    function _vaultHarvest() internal virtual override {
        IMasterchef(addresses.masterchef).withdraw(pid, 0);
    }
    
    function vaultSharesTotal() public virtual override view returns (uint256) {
        (uint256 amount,) = IMasterchef(addresses.masterchef).userInfo(pid, address(this));
        return amount;
    }
    
    function _emergencyVaultWithdraw() internal virtual override {
        IMasterchef(addresses.masterchef).emergencyWithdraw(pid);
    }
}