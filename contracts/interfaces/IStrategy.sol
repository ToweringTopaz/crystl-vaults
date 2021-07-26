// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

// For interacting with our own strategy
interface IStrategy {
    // Want address
    function wantAddress() external view returns (address);
    
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Want tokens currently deposited in masterhealer, etc
    function vaultTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Main want token compounding function
    function earn() external returns (uint256); //MUST RETURN 0 UNLESS CRYSTALLIZER VAULT

    // Transfer want tokens autoFarm -> strategy
    function deposit(address _userAddress, uint256 _wantAmt) external returns (uint256);

    // Transfer want tokens strategy -> vaultHealer
    function withdraw(address _userAddress, uint256 _wantAmt) external returns (uint256);
    
    // if it's a crystallizer vault
    function isCrystallizer() external returns (bool);
    
    // if it's the crystalcore vault
    function isCrystalCore() external returns (bool);
}