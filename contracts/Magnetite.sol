// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter.sol";
import "./libs/IUniFactory.sol";
import "./libs/IMagnetite.sol";
//Automatically generates and stores paths
contract Magnetite is Ownable, IMagnetite {

    struct PairData {
        IERC20 token;
        IUniPair lp;
        uint liquidity;
    }
    
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
    event SetPath(AutoPath indexed _auto, address router, IERC20[] path);

    mapping(bytes32 => IERC20[]) private _paths;

    //Adds or modifies a swap path
    function overridePath(address router, IERC20[] calldata _path) external {
        require(IAccessControl(owner()).hasRole(keccak256("PATH_SETTER"), msg.sender), "!auth");
        _setPath(router, _path, AutoPath.MANUAL);
    }

    function setAutoPath_(address router, IERC20[] calldata _path) external {
        require(msg.sender == address(this));
        _setPath(router, _path, AutoPath.AUTO);
    }
    function findAndSavePath(address _router, IERC20 a, IERC20 b) external returns (IERC20[] memory path) {
        IUniRouter router = IUniRouter(_router);
        path = getPathFromStorage(_router, a, b); // [A C E D B]
        if (path.length == 0) {
            path = generatePath(router, a, b);
            if (pathAuth()) {
                _setPath(_router, path, AutoPath.AUTO);

            }
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
    function pathAuth() internal virtual view returns (bool) {
        return msg.sender == tx.origin || msg.sender == owner() || IAccessControl(owner()).hasRole(keccak256("STRATEGY"), msg.sender);
    }

    function _setPath(address router, IERC20[] memory _path, AutoPath _auto) internal { 
        uint len = _path.length;

        bytes32 hashAB = keccak256(abi.encodePacked(router,_path[0], _path[len - 1]));
        bytes32 hashBA = keccak256(abi.encodePacked(router,_path[len - 1], _path[0]));
        IERC20[] storage pathAB = _paths[hashAB];
        if (pathAB.length > 0 && _auto != AutoPath.MANUAL) return;
        IERC20[] storage pathBA = _paths[hashBA];
        
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
            _setPath(router, _path, AutoPath.SUBPATH);
            IERC20 path0 = _path[0]; //temp to restore array after slicing
            assembly {
                _path := add(0x20,_path) // shift right in memory (we want _path[1:])
                mstore(_path, sub(len,1))
            }
            _setPath(router, _path, AutoPath.SUBPATH);
            assembly {
                mstore(_path, path0) //restore path[0]
                _path := sub(_path,0x20) //shift to initial start
                mstore(_path, len) //correct length
            }
        }
    }
    
    function generatePath(IUniRouter router, IERC20 a, IERC20 b) internal view returns (IERC20[] memory path) {
    
        IERC20[] memory _b = new IERC20[](2);
        _b[0] = b;
        IERC20 c = findPair(router, a, _b);
        _b[0] = a;
        IERC20 d = findPair(router, b, _b);
        
        path = new IERC20[](5);
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
        IERC20 e0 = findPair(router, d, _b);
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
        IERC20 e1 = findPair(router, c, _b);
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
    function findPair(IUniRouter router, IERC20 a, IERC20[] memory b) internal view returns (IERC20) {
        IUniFactory factory = IUniFactory(router.factory());
        
        PairData[] memory pairData = new PairData[](NUM_COMMON + b.length);

        IERC20[NUM_COMMON] memory allCom = allCommons(router);
        
        //populate pair tokens
        for (uint i; i < b.length; i++) {
            pairData[i].token = b[i];   
        }
        for (uint i; i < NUM_COMMON; i++) {
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
        require(pairData[best].liquidity > 0, "no liquidity");
        
        return pairData[best].token;
    }
    
    function compare(IUniRouter router, PairData memory x, PairData memory y) private pure returns (bool yBetter) {
        IERC20 wNative = router.WETH();
        uint xLiquidity = x.liquidity * (x.token == wNative ? WNATIVE_MULTIPLIER : 1);
        uint yLiquidity = y.liquidity * (y.token == wNative ? WNATIVE_MULTIPLIER : 1);
        return yLiquidity > xLiquidity;
    }

    function allCommons(IUniRouter router) private pure returns (IERC20[NUM_COMMON] memory tokens) {
        tokens = abi.decode(COMMON_TOKENS,(IERC20[6]));
        tokens[0] = router.WETH();
    }
    function setlength(IERC20[] memory array, uint n) internal pure returns (IERC20[] memory) {
        assembly { mstore(array, n) }
        return array;
    }
}