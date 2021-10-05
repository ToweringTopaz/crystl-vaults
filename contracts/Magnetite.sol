// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libs/IUniRouter.sol";

//Automatically generates and stores paths
contract Magnetite is Ownable {
    
    mapping(bytes32 => address[]) private _paths;
    address constant private WNATIVE = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; //wmatic
    address constant private COMMON1 = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; //usdc
    address constant private COMMON2 = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; //weth
    address constant private COMMON3 = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13; //quick
    address constant private COMMON4 = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F; //usdt
    address constant private COMMON5 = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063; //dai
    uint constant private NUM_COMMON = 6;
    uint constant private WNATIVE_MULTIPLIER = 30000; // Wnative weighted 3x
    uint constant private B_MULTIPLIER = 100000; // Token B direct swap weighted 10x
    uint constant private BASE_MULTIPLIER = 10000;
    
    struct PairData {
        address token;
        address lp;
        uint liquidity;
    }

    enum AutoPath { FALSE, SUBPATH, AUTO }
    event SetPath(AutoPath indexed _auto, address router, address[] path);
    
    //Adds or modifies a swap path
    function setPath(address router, address[] calldata _path) external onlyOwner {
        _setPath(router, _path, AutoPath.FALSE);
    }

    function setPath_(address router, address[] calldata _path) external {
        require(msg.sender == address(this));
        _setPath(router, _path, AutoPath.AUTO);
    }
    function _setPath(address router, address[] calldata _path, AutoPath _auto) internal { 
        uint len = _path.length;

        bytes32 hashAB = keccak256(abi.encodePacked(router,_path[0], _path[len - 1]));
        bytes32 hashBA = keccak256(abi.encodePacked(router,_path[len - 1], _path[0]));
        address[] storage pathAB = _paths[hashAB];
        if (pathAB.length > 0 && _auto != AutoPath.FALSE) return;
        address[] storage pathBA = _paths[hashBA];
        
        for (uint i; i < len; i++) {
            pathAB.push() = _path[i];
            pathBA.push() = _path[len - i - 1];
        }
            
        emit SetPath(_auto, router, pathAB);
        emit SetPath(_auto, router, pathBA);
        
        //fill sub-paths
        if (len > 2) {
            _setPath(router, _path[1:], AutoPath.SUBPATH);
            _setPath(router, _path[:len-1], AutoPath.SUBPATH);
        }
    }
    function getPath(address router, address a, address b) public view returns (address[] memory path) {
        if (a == b) {
            path = new address[](1);
            path[0] = a;
            return path;
        }
        path = _paths[keccak256(abi.encodePacked(router, a, b))];
    }
    function findPath(address router, address a, address b) public returns (address[] memory path) {
        path = getPath(router, a, b); // [A C E D B]
        if (path.length == 0) {
            path = generatePath(router, a, b);
            assert(path.length > 1);
            for (uint i; i < path.length; i++) {
                for (uint j; j < path.length; j++) {
                    assert(i == j ||path[i] != path[j]); //no repeating steps
                }
            }
            this.setPath_(router, path);
        }
    }
    function generatePath(address router, address a, address b) private view returns (address[] memory path) {
    
        address[] memory _b = new address[](2);
        _b[0] = b;
        address c = findPair(router, a, _b);
        _b[0] = a;
        address d = findPair(router, b, _b);
        if (c == b || d == a) {
            path = new address[](2);
            path[0] = a;
            path[1] = b;
            return path;
        } else if (c == d) {
            path = new address[](3);
            path[0] = a;
            path[1] = c;
            path[2] = b;
            return path;
        }
        _b[1] = c;
        address e0 = findPair(router, d, _b);
        if (e0 == a) {
            path = new address[](3);
            path[0] = a;
            path[1] = d;
            path[2] = b;
            return path;
        } else if (e0 == c) {
            path = new address[](4);
            path[0] = a;
            path[1] = c;
            path[2] = d;
            path[3] = b;
            return path;
        }
        _b[0] = b;
        _b[1] = d;
        address e1 = findPair(router, c, _b);
        if (e1 == b) {
            path = new address[](3);
            path[0] = a;
            path[1] = c;
            path[2] = b;
            return path;
        } else if (e1 == d) {
            path = new address[](4);
            path[0] = a;
            path[1] = c;
            path[2] = d;
            path[3] = b;
            return path;
        } else {
            require (e1 == e0, "no path found");
            path = new address[](5);
            path[0] = a;
            path[1] = c;
            path[2] = e0;
            path[3] = d;
            path[4] = b;
            return path;
        }
    }   
    function findPair(address router, address a, address[] memory b) private view returns (address) {
        IUniFactory factory = IUniFactory(IUniRouter02(router).factory());
        
        PairData[] memory pairData = new PairData[](NUM_COMMON + b.length);
        address[] memory allCom = allCommons();
        
        //populate pair tokens
        for (uint i; i < b.length; i++) {
            pairData[i].token = b[i];   
        }
        for (uint i; i < NUM_COMMON; i++) {
            pairData[i+b.length].token = allCom[i];
        }
        
        //calculate liquidity
        for (uint i; i < NUM_COMMON + 1; i++) {
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
        for (uint i; i < b.length; i++) {
            pairData[i].liquidity = pairData[i].liquidity * B_MULTIPLIER / BASE_MULTIPLIER;
        }
        uint best;
        for (uint i = 1; i < NUM_COMMON + 1; i++) {
            if (compare(pairData[best], pairData[i])) best = i;
        }
        require(pairData[best].liquidity > 0, "no liquidity");
        
        return pairData[best].token;
    }
    
    function compare(PairData memory x, PairData memory y) private pure returns (bool yBetter) {
        uint xmul = x.token == WNATIVE ? WNATIVE_MULTIPLIER : BASE_MULTIPLIER;
        uint ymul = y.token == WNATIVE ? WNATIVE_MULTIPLIER : BASE_MULTIPLIER;
        return y.liquidity * ymul > x.liquidity * xmul;
    }
    
    function allCommons() private pure returns (address[] memory tokens) {
        tokens = new address[](NUM_COMMON);
        tokens[0] = WNATIVE;
        tokens[1] = COMMON1;
        tokens[2] = COMMON2;
        tokens[3] = COMMON3;
        tokens[4] = COMMON4;
        tokens[5] = COMMON5;
    }
    function isCommon(address token) private pure returns (bool) {
        address[] memory tokens = allCommons();
        for (uint i; i < tokens.length; i++) {
            if (token == tokens[i]) return true;
        }
        return false;
    }
}