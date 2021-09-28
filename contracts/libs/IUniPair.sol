// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniPair is IERC20 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function mint(address to) external returns (uint liquidity);
    function decimals() external view returns (uint8);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 lastUpdateBlock);
}