// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "./interfaces/IUniPair.sol";
import "./interfaces/IUniRouter.sol";
import "./interfaces/IUniFactory.sol";
import "./interfaces/IMagnetite.sol";

//Automatically generates and stores paths
contract Magnetite is Ownable, IMagnetite {

    struct PairData {
        IERC20 token;
        IUniPair lp;
        uint liquidity;
    }
    
    uint constant private WNATIVE_MULTIPLIER = 3; // Wnative weighted 3x
    uint constant private B_MULTIPLIER = 10; // Token B direct swap weighted 10x

    event SetPath(bool manual, address router, IERC20[] path);

    mapping(bytes32 => IERC20[]) private _paths;
    mapping(bytes32 => bool) private _manualPath;


    constructor() {
        require (IUniRouter(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff).factory() == IUniFactory(0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32), 
            "This contract only works on polygon mainnet and its test forks");  //quickswap router/factory
    }


    //Adds or modifies a swap path
    function overridePath(address router, IERC20[] calldata _path) external {
        require(msg.sender == owner() || IAccessControl(owner()).hasRole(keccak256("PATH_SETTER"), msg.sender), "!auth");
        _setPath(router, _path, true);
    }

    function findAndSavePath(address _router, IERC20 a, IERC20 b) external returns (IERC20[] memory path) {
        IUniRouter router = IUniRouter(_router);
        path = getPathFromStorage(_router, a, b); // [A C E D B]

        console.log("magnetite find and save len", path.length);
        if (path.length == 0) {
            path = generatePath(router, a, b);
            console.log("magnetite find and save new len", path.length);
            _setPath(_router, path, false);
        }
    }

    function viewPath(address _router, IERC20 a, IERC20 b) external view returns (IERC20[] memory path) {
        IUniRouter router = IUniRouter(_router);
        path = getPathFromStorage(_router, a, b); // [A C E D B]
        if (path.length == 0) {
            path = generatePath(router, a, b);
        }
    }
    function getPathFromStorage(address router, IERC20 a, IERC20 b) public view returns (IERC20[] memory path) {
        if (a == b) {
            path = new IERC20[](1);
            path[0] = a;
            return path;
        }
        path = _paths[keccak256(abi.encodePacked(router, a, b))];
    }

    function _setPath(address router, IERC20[] memory _path, bool _manual) internal { 
        uint len = _path.length;

        bytes32 hashAB = keccak256(abi.encodePacked(router,_path[0], _path[len - 1]));
        bytes32 hashBA = keccak256(abi.encodePacked(router,_path[len - 1], _path[0]));
        IERC20[] storage pathAB = _paths[hashAB];
        if (_manual) {
            _manualPath[hashAB] = true;
            _manualPath[hashBA] = true;
        } else {
            if (pathAB.length > 0) return;
        }
        console.log("setting path", address(_path[0]), address(_path[len - 1]));
        IERC20[] storage pathBA = _paths[hashBA];
        
        for (uint i; i < len; i++) {
            pathAB.push() = _path[i];
            pathBA.push() = _path[len - i - 1];
        }
            
        emit SetPath(_manual, router, pathAB);
        emit SetPath(_manual, router, pathBA);
        
        //fill sub-paths
        if (len > 2) {
            assembly { 
                mstore(_path, sub(len,1)) //reduce length by 1 (_we want _path[:len-1])
            } 
            _setPath(router, _path, false);
            IERC20 path0 = _path[0]; //temp to restore array after slicing
            assembly {
                _path := add(0x20,_path) // shift right in memory (we want _path[1:])
                mstore(_path, sub(len,1))
            }
            _setPath(router, _path, false);
            assembly {
                mstore(_path, path0) //restore path[0]
                _path := sub(_path,0x20) //shift to initial start
                mstore(_path, len) //correct length
            }
        }
    }
    
    function generatePath(IUniRouter router, IERC20 a, IERC20 b) internal view returns (IERC20[] memory path) {
    
        console.log("magnetite generatePath");
        if (a == b) {
            path = new IERC20[](1);
            path[0] = a;
            return path;
        }

        IERC20[] memory _b = new IERC20[](2);
        _b[0] = b;
        IERC20 c = findPair(router, a, _b);
        _b[0] = a;
        IERC20 d = findPair(router, b, _b);

        path = new IERC20[](5);
        path[0] = a;

        if (c == b || d == a) {
            path[1] = b;
            setlength(path, 2);
            return path;
        } else if (c == d) {
            path[1] = c;
            path[2] = b;
            setlength(path, 3);
            return path;
        }
        _b[1] = c;
        IERC20 e0 = findPair(router, d, _b);
        if (e0 == a) {
            path[1] = d;
            path[2] = b;
            setlength(path, 3);
            return path;
        }
        path[1] = c;
        if (e0 == c) {
            path[2] = d;
            path[3] = b;
            setlength(path, 4);
            return path;
        }
        _b[0] = b;
        _b[1] = d;
        IERC20 e1 = findPair(router, c, _b);
        if (e1 == b) {
            path[2] = b;
            setlength(path, 3);
            return path;
        }
        if (e1 == d) {
            path[2] = d;
            path[3] = b;
            setlength(path, 4);
            return path;
        }
        if (e1 != e0) {
            console.log("a,b:", address(a), address(b));
            console.log("e0,e1:", address(e0), address(e1));
            revert("no path found");
        }
        path[2] = e0;
        path[3] = d;
        path[4] = b;
        return path;
    }   
    function findPair(IUniRouter router, IERC20 a, IERC20[] memory b) internal view returns (IERC20) {
        IUniFactory factory = IUniFactory(router.factory());
        console.log("findpair", address(a), address(b[0]));
        console.log(address(b[1]));
        IERC20[] memory allCom = commonTokens(router);
        PairData[] memory pairData = new PairData[](allCom.length + b.length);

        
        
        //populate pair tokens
        for (uint i; i < b.length; i++) {
            pairData[i].token = b[i];   
        }
        for (uint i; i < allCom.length; i++) {
            pairData[i+b.length].token = allCom[i];
        }
        
        //calculate liquidity
        for (uint i; i < pairData.length; i++) {
            IUniPair pair = factory.getPair(a, pairData[i].token);
            if (address(pair) != address(0)) {
                uint liq = a.balanceOf(address(pair));
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
        console.log("no liq :(");
        require(pairData[best].liquidity > 0, "no liquidity");
        
        return pairData[best].token;
    }
    
    function compare(IUniRouter router, PairData memory x, PairData memory y) private pure returns (bool yBetter) {
        IERC20 wNative = router.WETH();
        uint xLiquidity = x.liquidity * (x.token == wNative ? WNATIVE_MULTIPLIER : 1);
        uint yLiquidity = y.liquidity * (y.token == wNative ? WNATIVE_MULTIPLIER : 1);
        return yLiquidity > xLiquidity;
    }

    function commonTokens(IUniRouter router) private pure returns (IERC20[] memory tokens) {
        tokens = new IERC20[](6);
        tokens[0] = router.WETH();
        tokens[1] = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); //usdc
        tokens[2] = IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619); //weth
        tokens[3] = IERC20(0x831753DD7087CaC61aB5644b308642cc1c33Dc13); //quick
        tokens[4] = IERC20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F); //usdt
        tokens[5] = IERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063); //dai
    }
    function setlength(IERC20[] memory array, uint n) internal pure {
        assembly { mstore(array, n) }
    }

    function isManualPath(IUniRouter router, IERC20 tokenA, IERC20 tokenB) external view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(router,tokenA,tokenB));
        return _manualPath[hash];
    }
}