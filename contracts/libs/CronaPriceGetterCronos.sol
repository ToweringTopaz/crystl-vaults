// SPDX-License-Identifier: GPL
pragma solidity ^0.8.4;

// This library provides simple price calculations for CronaSwap tokens, accounting
// for commonly used pairings. Will break if USDT, BUSD, or DAI goes far off peg.
// Should NOT be used as the sole oracle for sensitive calculations such as 
// liquidation, as it is vulnerable to manipulation by flash loans, etc. BETA
// SOFTWARE, PROVIDED AS IS WITH NO WARRANTIES WHATSOEVER.

// Cronos mainnet version

interface ICronaPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function totalSupply() external view returns (uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
}
interface IERC20 {
    function decimals() external view returns (uint8);
}

library CronaPriceGetter {
    
    address public constant FACTORY = 0x4D7aa1bC7CF5437031f9cD6881422C1204dd4592; //CronaSwap Factory on Cronos testnet (338)
    bytes32 public constant INITCODEHASH = hex'5613c6922c58d91f43cb8062ed0cd1698874e4f10ec55ee08ca2a51bff06cff7'; // for pairs created by CronaFactory
    
    //Returned prices calculated with this precision (18 decimals)
    uint public constant DECIMALS = 18;
    uint private constant PRECISION = 1e18; //1e18 == $1
    
    //Token addresses
    address constant WCRO = 0x77e66C840e7198C95500f7f547543E1466C5CB2c;
    // address constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address constant USDC = 0x25f0965F285F03d6F6B3B21c8EC3367412Fd0ef6;
    // address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    // address constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

    //Crona LP addresses
    // address private constant WCRO_USDT_PAIR = 0x65D43B64E3B31965Cd5EA367D4c2b94c03084797;
    // address private constant WCRO_DAI_PAIR = 0x84964d9f9480a1dB644c2B2D1022765179A40F68;
    address private constant WCRO_USDC_PAIR = 0x3AD39bFD1714D6F9ED2963b46af770183b93D0e2;
    
    // address private constant WETH_USDT_PAIR = 0x7B2dD4bab4487a303F716070B192543eA171d3B2;
    // address private constant USDC_WETH_PAIR = 0x84964d9f9480a1dB644c2B2D1022765179A40F68;
    // address private constant WETH_DAI_PAIR = 0xb724E5C1Aef93e972e2d4b43105521575f4ca855;

    //Normalized to specified number of decimals based on token's decimals and
    //specified number of decimals
    function getPrice(address token, uint _decimals) external view returns (uint) {
        return normalize(getRawPrice(token), token, _decimals);
    }

    function getLPPrice(address token, uint _decimals) external view returns (uint) {
        return normalize(getRawLPPrice(token), token, _decimals);
    }
    function getPrices(address[] calldata tokens, uint _decimals) external view returns (uint[] memory prices) {
        prices = getRawPrices(tokens);
        
        for (uint i; i < prices.length; i++) {
            prices[i] = normalize(prices[i], tokens[i], _decimals);
        }
    }
    function getLPPrices(address[] calldata tokens, uint _decimals) external view returns (uint[] memory prices) {
        prices = getRawLPPrices(tokens);
        
        for (uint i; i < prices.length; i++) {
            prices[i] = normalize(prices[i], tokens[i], _decimals);
        }
    }
    
    //returns the price of any token in USD based on common pairings; zero on failure
    function getRawPrice(address token) internal view returns (uint) {
        uint pegPrice = pegTokenPrice(token);
        if (pegPrice != 0) return pegPrice;
        
        return getRawPrice(token, getCROPrice());
    }
    
    //returns the prices of multiple tokens, zero on failure
    function getRawPrices(address[] calldata tokens) public view returns (uint[] memory prices) {
        prices = new uint[](tokens.length);
        uint croPrice = getCROPrice();
        // uint ethPrice = getETHPrice();
        
        for (uint i; i < prices.length; i++) {
            address token = tokens[i];
            
            uint pegPrice = pegTokenPrice(token, croPrice);
            if (pegPrice != 0) prices[i] = pegPrice;
            else prices[i] = getRawPrice(token, croPrice);
        }
    }
    
    //returns the value of a LP token if it is one, or the regular price if it isn't LP
    function getRawLPPrice(address token) internal view returns (uint) {
        uint pegPrice = pegTokenPrice(token);
        if (pegPrice != 0) return pegPrice;
        
        return getRawLPPrice(token, getCROPrice());
    }
    //returns the prices of multiple tokens which may or may not be LPs
    function getRawLPPrices(address[] calldata tokens) internal view returns (uint[] memory prices) {
        prices = new uint[](tokens.length);
        uint croPrice = getCROPrice();
        // uint ethPrice = getETHPrice();
        
        for (uint i; i < prices.length; i++) {
            address token = tokens[i];
            
            uint pegPrice = pegTokenPrice(token, croPrice);
            if (pegPrice != 0) prices[i] = pegPrice;
            else prices[i] = getRawLPPrice(token, croPrice);
        }
    }
    //returns the current USD price of CRO based on primary stablecoin pairs
    function getCROPrice() internal view returns (uint) {
        // (uint wcroReserve0, uint usdtReserve,) = ICronaPair(WCRO_USDT_PAIR).getReserves();
        // (uint wcroReserve1, uint daiReserve,) = ICronaPair(WCRO_DAI_PAIR).getReserves();
        (uint wcroReserve2, uint usdcReserve,) = ICronaPair(WCRO_USDC_PAIR).getReserves();
        // uint wcroTotal = wcroReserve0 + wcroReserve1 + wcroReserve2;
        // uint usdTotal = daiReserve + (usdcReserve + usdtReserve)*1e12; // 1e18 USDC/T == 1e30 DAI
        
        return usdcReserve * PRECISION / wcroReserve2; 
    }
    
    //returns the current USD price of ETH based on primary stablecoin pairs
    // function getETHPrice() internal view returns (uint) {
    //     (uint wethReserve0, uint usdtReserve,) = ICronaPair(WETH_USDT_PAIR).getReserves();
    //     (uint usdcReserve, uint wethReserve1,) = ICronaPair(USDC_WETH_PAIR).getReserves();
    //     (uint wethReserve2, uint daiReserve,) = ICronaPair(WETH_DAI_PAIR).getReserves();
    //     uint wethTotal = wethReserve0 + wethReserve1 + wethReserve2;
    //     uint usdTotal = daiReserve + (usdcReserve + usdtReserve)*1e12; // 1e18 USDC/T == 1e30 DAI
        
    //     return usdTotal * PRECISION / wethTotal; 
    // }
    
    //Calculate LP token value in USD. Generally compatible with any UniswapV2 pair but will always price underlying
    //tokens using crona prices. If the provided token is not a LP, it will attempt to price the token as a
    //standard token. This is useful for MasterChef farms which stake both single tokens and pairs
    function getRawLPPrice(address lp, uint croPrice) internal view returns (uint) {
        
        //if not a LP, handle as a standard token
        try ICronaPair(lp).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            
            address token0 = ICronaPair(lp).token0();
            address token1 = ICronaPair(lp).token1();
            uint totalSupply = ICronaPair(lp).totalSupply();
            
            //price0*reserve0+price1*reserve1
            uint totalValue = normalize(getRawPrice(token0, croPrice), token0, DECIMALS) * reserve0 
                + normalize(getRawPrice(token1, croPrice), token1, DECIMALS) * reserve1;
            
            return totalValue / totalSupply;
            
        } catch {
            return getRawPrice(lp, croPrice);
        }
    }

    // checks for primary tokens and returns the correct predetermined price if possible, otherwise calculates price
    function getRawPrice(address token, uint croPrice) internal view returns (uint) {
        uint pegPrice = pegTokenPrice(token, croPrice);
        if (pegPrice != 0) return pegPrice;

        uint numTokens;
        uint pairedValue;
        
        uint lpTokens;
        uint lpValue;
        
        (lpTokens, lpValue) = pairTokensAndValue(token, WCRO);
        numTokens += lpTokens;
        pairedValue += lpValue;
        
        // (lpTokens, lpValue) = pairTokensAndValue(token, WETH);
        // numTokens += lpTokens;
        // pairedValue += lpValue;
        
        // (lpTokens, lpValue) = pairTokensAndValue(token, DAI);
        // numTokens += lpTokens;
        // pairedValue += lpValue;
        
        (lpTokens, lpValue) = pairTokensAndValue(token, USDC);
        numTokens += lpTokens;
        pairedValue += lpValue;
        
        // (lpTokens, lpValue) = pairTokensAndValue(token, USDT);
        // numTokens += lpTokens;
        // pairedValue += lpValue;
        
        if (numTokens == 0) return 0;
        return pairedValue / numTokens;
    }
    //if one of the peg tokens, returns that price, otherwise zero
    function pegTokenPrice(address token, uint croPrice) private pure returns (uint) {
        if (token == USDC) return PRECISION;
        if (token == WCRO) return croPrice;
        // if (token == WETH) return ethPrice;
        // if (token == DAI) return PRECISION;
        return 0;
    }
    function pegTokenPrice(address token) private view returns (uint) {
        if (token == USDC) return PRECISION;
        if (token == WCRO) return getCROPrice();
        // if (token == WETH) return getETHPrice();
        // if (token == DAI) return PRECISION;
        return 0;
    }

    //returns the number of tokens and the USD value within a single LP. peg is one of the listed primary, pegPrice is the predetermined USD value of this token
    function pairTokensAndValue(address token, address peg) private view returns (uint tokenNum, uint pegValue) {

        address tokenPegPair = pairFor(token, peg);
        
        // if the address has no contract deployed, the pair doesn't exist
        uint256 size;
        assembly { size := extcodesize(tokenPegPair) }
        if (size == 0) return (0,0);
        
        try ICronaPair(tokenPegPair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            uint reservePeg;
            (tokenNum, reservePeg) = token < peg ? (reserve0, reserve1) : (reserve1, reserve0);
            pegValue = reservePeg * pegTokenPrice(peg);
        } catch {
            return (0,0);
        }

    }
    //normalize a token price to a specified number of decimals
    function normalize(uint price, address token, uint _decimals) private view returns (uint) {
        uint tokenDecimals;
        
        try IERC20(token).decimals() returns (uint8 dec) {
            tokenDecimals = dec;
        } catch {
            tokenDecimals = 18;
        }

        if (tokenDecimals + _decimals <= 2*DECIMALS) return price / 10**(2*DECIMALS - tokenDecimals - _decimals);
        else return price * 10**(_decimals + tokenDecimals - 2*DECIMALS);
    
    }
    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB) private pure returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                FACTORY,
                keccak256(abi.encodePacked(token0, token1)),
                INITCODEHASH
        )))));
    }
}