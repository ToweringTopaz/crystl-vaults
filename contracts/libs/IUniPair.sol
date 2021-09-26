// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface IUniPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function mint(address to) external returns (uint liquidity);
}