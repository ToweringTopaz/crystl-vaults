// SPDX-License-Identifier: GPL
pragma solidity ^0.8.6;

import "@uniswap/v2-core@1.0.1/contracts/interfaces/IUniswapV2Pair.sol";
import "./UniV2AMMData.sol";

library GibbonLibrary {
    using UniV2AMMData for AmmData;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'ApeLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ApeLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(AmmData amm, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                amm.factory(),
                keccak256(abi.encodePacked(token0, token1)),
                amm.pairCodeHash()
        )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(AmmData amm, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        require(tokenA != tokenB, 'ApeLibrary: IDENTICAL_ADDRESSES');
        address pair = pairFor(amm, tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'ApeLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'ApeLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(AmmData amm, uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'ApeLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'ApeLibrary: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn * (1000 - amm.fee());
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
    
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(AmmData amm, uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amm.fee() <= 1000, 'GibbonLibrary: INVALID_SWAP FEE');
        require(amountOut > 0, 'ApeLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'ApeLibrary: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * (1000 - amm.fee());
        amountIn = (numerator / denominator) + 1;
    }
    
    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(AmmData amm, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'GibbonLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(amm, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amm, amounts[i], reserveIn, reserveOut);
        }
    }
    
    //chained getAmountIn calculations where each pair can use a different AMM to trade
    function getAmountsIn(AmmData[] memory amms, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(amms.length >= 1 && path.length == amms.length + 1, 'GibbonLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amms.length] = amountOut; //amms.length == amounts.length - 1
        for (uint i = amms.length; i > 0; i--) { //amms.length == path.length - 1
            (uint reserveIn, uint reserveOut) = getReserves(amms[i], path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amms[i], amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(AmmData amm, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'GibbonLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(amm, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amm, amounts[i], reserveIn, reserveOut);
        }
    }
    
    //chained getAmountOut calculations where each pair can use a different AMM to trade
    function getAmountsOut(AmmData[] memory amms, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(amms.length >= 1 && path.length == amms.length + 1, 'GibbonLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < amms.length; i++) { //path.length - 1
            (uint reserveIn, uint reserveOut) = getReserves(amms[i], path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amms[i], amounts[i], reserveIn, reserveOut);
        }
    }

    
}