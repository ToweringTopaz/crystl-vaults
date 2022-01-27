// File contracts/interfaces/ITreasury.sol

pragma solidity 0.7.5;

interface ITreasury {
    function valueOfToken( address _principalTokenAddress, uint _amount ) external view returns ( uint value_ );
    function payoutToken() external view returns (address);
    function deposit(address _principleTokenAddress, uint _amountPrincipleToken, uint _amountPayoutToken) external;
}