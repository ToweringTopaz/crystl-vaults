// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IUniRouter.sol";

//The bulk of the magnetite code is here
library LibMagnetite {
    using LibMagnetite for address[];
    
    struct PairData {
        address token;
        address lp;
        uint liquidity;
    }
    
    address constant private WNATIVE_DEFAULT = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    bytes constant private COMMON_TOKENS = abi.encode([
        address(0), //slot for wnative
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, //usdc
        0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, //weth
        0x831753DD7087CaC61aB5644b308642cc1c33Dc13, //quick
        0xc2132D05D31c914a87C6611C10748AEb04B58e8F, //usdt
        0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063  //dai
    ]);

    uint constant private NUM_COMMON = 6;
    uint constant private WNATIVE_MULTIPLIER = 3; // Wnative weighted 3x
    uint constant private B_MULTIPLIER = 10; // Token B direct swap weighted 10x

    enum AutoPath { MANUAL, SUBPATH, AUTO }
    event SetPath(AutoPath indexed _auto, address router, address[] path);

    function _setPath(mapping(bytes32 => address[]) storage _paths, address router, address[] memory _path, AutoPath _auto) public { 
        uint len = _path.length;

        bytes32 hashAB = keccak256(abi.encodePacked(router,_path[0], _path[len - 1]));
        bytes32 hashBA = keccak256(abi.encodePacked(router,_path[len - 1], _path[0]));
        address[] storage pathAB = _paths[hashAB];
        if (pathAB.length > 0 && _auto != AutoPath.MANUAL) return;
        address[] storage pathBA = _paths[hashBA];
        
        for (uint i; i < len; i++) {
            pathAB.push() = _path[i];
            pathBA.push() = _path[len - i - 1];
        }
            
        emit SetPath(_auto, router, pathAB);
        emit SetPath(_auto, router, pathBA);
        
        //fill sub-paths
        if (len > 2) {
            assembly { 
                mstore(_path, sub(len,1)) //reduce length by 1 (_we want _path[:len-1])
            } 
            _setPath(_paths, router, _path, AutoPath.SUBPATH);
            address path0 = _path[0]; //temp to restore array after slicing
            assembly {
                _path := add(0x20,_path) // shift right in memory (we want _path[1:])
                mstore(_path, sub(len,1))
            }
            _setPath(_paths, router, _path, AutoPath.SUBPATH);
            assembly {
                mstore(_path, path0) //restore path[0]
                _path := sub(_path,0x20) //shift to initial start
                mstore(_path, len) //correct length
            }
        }
    }
    
    function generatePath(address router, address a, address b) public view returns (address[] memory path) {
    
        address[] memory _b = new address[](2);
        _b[0] = b;
        address c = findPair(router, a, _b);
        _b[0] = a;
        address d = findPair(router, b, _b);
        
        path = new address[](5);
        path[0] = a;
        
        if (c == b || d == a) {
            path[1] = b;
            return path;
        } else if (c == d) {
            path[1] = c;
            path[2] = b;
            return setlength(path, 3);
        }
        _b[1] = c;
        address e0 = findPair(router, d, _b);
        if (e0 == a) {
            path[1] = d;
            path[2] = b;
            return setlength(path, 3);
        }
        path[1] = c;
        if (e0 == c) {
            path[2] = d;
            path[3] = b;
            return setlength(path, 4);
        }
        _b[0] = b;
        _b[1] = d;
        address e1 = findPair(router, c, _b);
        if (e1 == b) {
            path[2] = b;
            return setlength(path, 3);
        }
        if (e1 == d) {
            path[2] = d;
            path[3] = b;
            return setlength(path, 4);
        }
        require (e1 == e0, "no path found");
        path[2] = e0;
        path[3] = d;
        path[4] = b;
        return path;
    }   
    function findPair(address router, address a, address[] memory b) public view returns (address) {
        IUniFactory factory = IUniFactory(IUniRouter02(router).factory());
        
        PairData[] memory pairData = new PairData[](NUM_COMMON + b.length);

        address[NUM_COMMON] memory allCom = allCommons(router);
        
        //populate pair tokens
        for (uint i; i < b.length; i++) {
            pairData[i].token = b[i];   
        }
        for (uint i; i < NUM_COMMON; i++) {
            pairData[i+b.length].token = allCom[i];
        }
        
        //calculate liquidity
        for (uint i; i < pairData.length; i++) {
            address pair = factory.getPair(a, pairData[i].token);
            if (pair != address(0)) {
                uint liq = IERC20(a).balanceOf(pair);
                if (liq > 0) {
                    pairData[i].lp = pair;
                    pairData[i].liquidity = liq;
                }
            }
        }
        //find weighted most liquid pair
        for (uint i; i < pairData.length; i++) {
            pairData[i].liquidity = pairData[i].liquidity * B_MULTIPLIER;
        }
        uint best;
        for (uint i = 1; i < pairData.length; i++) {
            if (compare(router, pairData[best], pairData[i])) best = i;
        }
        require(pairData[best].liquidity > 0, "no liquidity");
        
        return pairData[best].token;
    }
    
    function compare(address router, PairData memory x, PairData memory y) private pure returns (bool yBetter) {
        address wNative = wnative(router);
        uint xLiquidity = x.liquidity * (x.token == wNative ? WNATIVE_MULTIPLIER : 1);
        uint yLiquidity = y.liquidity * (y.token == wNative ? WNATIVE_MULTIPLIER : 1);
        return yLiquidity > xLiquidity;
    }

    function allCommons(address router) private pure returns (address[NUM_COMMON] memory tokens) {
        tokens = abi.decode(COMMON_TOKENS,(address[6]));
        tokens[0] = wnative(router);
    }
    function wnative(address router) private pure returns (address) {
        try IUniRouter02(router).WETH() returns (address weth) {
            return weth;
        } catch {
            return WNATIVE_DEFAULT;
        }
    }
    function getPathFromStorage(mapping(bytes32 => address[]) storage _paths, address router, address a, address b) private view returns (address[] storage path) {
        path = _paths[keccak256(abi.encodePacked(router, a, b))];
    }
    function setlength(address[] memory array, uint n) private pure returns (address[] memory) {
        assembly { mstore(array, n) }
        return array;
    }
}