// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "./interfaces/IUniPair.sol";
import "./interfaces/IUniRouter.sol";
import "./interfaces/IUniFactory.sol";
import "./interfaces/IMagnetite.sol";


//Automatically generates and stores paths
contract Magnetite is OwnableUpgradeable, IMagnetite {


    struct PairData {
        IERC20 token;
        IUniPair lp;
        uint liquidity;
    }
    
    struct Path {
        bool manual;
        IERC20[5] tokens;
    }

    uint constant private WNATIVE_MULTIPLIER = 3; // Wnative weighted 3x
    uint constant private B_MULTIPLIER = 10; // Token B direct swap weighted 10x

    event SetPath(bool manual, address router, IERC20[] path);
    bytes32[1] private __RESERVED__;
    mapping(bytes32 => Path) private _paths;

    constructor(address vhAuth) {
        require(block.chainid > 30000 || block.chainid == 137 || block.chainid == 25 || block.chainid == 56, "unsupported chain");
        _init(vhAuth);

        (COMMON_1, COMMON_2, COMMON_3, COMMON_4, COMMON_5) = block.chainid == 25 ? ( //cronos
            0xc21223249CA28397B4B6541dfFaEcC539BfF0c59,
            0xe44Fd7fCb2b1581822D0c862B68222998a0c299a,
            0x062E66477Faf219F25D27dCED647BF57C3107d52,
            0x66e428c3f67a68878562e79A0234c1F83c208770,
            0xF2001B145b43032AAF5Ee2884e456CCd805F677D
        ) : ( block.chainid == 56 ? ( //bsc
            0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, //usdc
            0x2170Ed0880ac9A755fd29B2688956BD959F933F8, //weth
            0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c, //wbtc: actually btcb on BNB Chain
            0x55d398326f99059fF775485246999027B3197955, //usdt
            0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3 //dai
        ) : ( //polygon
            0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, //usdc
            0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, //weth
            0x831753DD7087CaC61aB5644b308642cc1c33Dc13, //quick
            0xc2132D05D31c914a87C6611C10748AEb04B58e8F, //usdt
            0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063 //dai

        ));

    }

    function _init(address vhAuth) public virtual initializer {
        _transferOwnership(vhAuth);
    }

    //Adds or modifies a swap path
    function overridePath(address router, IERC20[] calldata _path) external {
        require(IAccessControl(owner()).hasRole(keccak256("PATH_SETTER"), msg.sender), "!auth");
        _setPath(router, _path, true);
    }

    function findAndSavePath(address _router, IERC20 a, IERC20 b) external returns (IERC20[] memory path) {

        IUniRouter router = IUniRouter(_router);
        path = getPathFromStorage(_router, a, b); // [A C E D B]

        //console.log("magnetite find and save len", path.length);
        if (path.length == 0) {
            path = generatePath(router, a, b);
            //console.log("magnetite find and save new len", path.length);
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
        IERC20[5] storage tokens = _paths[keccak256(abi.encodePacked(router, a, b))].tokens;

        if (tokens[0] == IERC20(address(type(uint160).max))) {
            path = new IERC20[](2);
            path[0] = a;
            path[1] = b;
            return path;            
        } else if (tokens[0] != IERC20(address(0))) {
            path = new IERC20[](7);
            path[0] = a;
            uint i;
            while(i < 4) {
                IERC20 token = tokens[i];
                if (token == IERC20(address(0))) break;
                path[++i] = token;

            }
            path[++i] = b;
            assembly("memory-safe") {
                mstore(path, add(i, 1))
            }
        }
    }

    function _setPath(address router, IERC20[] memory _path, bool _manual) internal { 
        uint len = _path.length;
        bytes32 hashAB = keccak256(abi.encodePacked(router,_path[0], _path[len - 1]));
        IERC20[5] storage tokens = _paths[hashAB].tokens;
        if (_manual) {
            _paths[hashAB].manual = true;
        } else {
            if (tokens[0] > IERC20(address(0))) return;
        }

        uint i;
        if (len == 2) {
            tokens[0] = IERC20(address(type(uint160).max));
            i = 1;
        } else {
            for (; i < len - 2; i++) {
                tokens[i] = _path[i+1];
            }
        }
        for (; i < 5; i++) {
            if (tokens[i] == IERC20(address(0))) break;
            else delete tokens[i];
        }

        emit SetPath(_manual, router, _path);
    }
    
    function generatePath(IUniRouter router, IERC20 a, IERC20 b) internal view returns (IERC20[] memory path) {
        require(gasleft() > 800000, "magnetite: need more gas");
        //console.log("magnetite generatePath");
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
            //console.log("a,b:", address(a), address(b));
            //console.log("e0,e1:", address(e0), address(e1));
            revert("no path found");
        }
        path[2] = e0;
        path[3] = d;
        path[4] = b;
        return path;
    }   
    function findPair(IUniRouter router, IERC20 a, IERC20[] memory b) internal view returns (IERC20) {
        IUniFactory factory = IUniFactory(router.factory());
        //console.log("findpair", address(a), address(b[0]));
        //console.log(address(b[1]));
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
        //console.log("no liq :(");
        require(pairData[best].liquidity > 0, "no liquidity");
        
        return pairData[best].token;
    }
    
    function compare(IUniRouter router, PairData memory x, PairData memory y) private pure returns (bool yBetter) {
        IERC20 wNative = router.WETH();
        uint xLiquidity = x.liquidity * (x.token == wNative ? WNATIVE_MULTIPLIER : 1);
        uint yLiquidity = y.liquidity * (y.token == wNative ? WNATIVE_MULTIPLIER : 1);
        return yLiquidity > xLiquidity;
    }

    address immutable COMMON_1;
    address immutable COMMON_2;
    address immutable COMMON_3;
    address immutable COMMON_4;
    address immutable COMMON_5;

    function commonTokens(IUniRouter router) internal view returns (IERC20[] memory tokens) {
        tokens = new IERC20[](6);
        tokens[0] = router.WETH();
        tokens[1] = IERC20(COMMON_1);
        tokens[2] = IERC20(COMMON_2);
        tokens[3] = IERC20(COMMON_3);
        tokens[4] = IERC20(COMMON_4);
        tokens[5] = IERC20(COMMON_5);
    }
    //dangerous operation, only use if you know what you're doing
    function setlength(IERC20[] memory array, uint n) private pure {
        assembly { mstore(array, n) }
    }

    function isManualPath(IUniRouter router, IERC20 tokenA, IERC20 tokenB) external view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(router,tokenA,tokenB));
        return _paths[hash].manual;
    }
}