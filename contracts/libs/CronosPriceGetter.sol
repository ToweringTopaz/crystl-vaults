// SPDX-License-Identifier: GPL
pragma solidity ^0.8.4;

import "./AMMData.sol";
import "./IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// This library provides simple price calculations for Crodex tokens, accounting
// for commonly used pairings. Will break if USDT, BUSD, or DAI goes far off peg.
// Should NOT be used as the sole oracle for sensitive calculations such as 
// liquidation, as it is vulnerable to manipulation by flash loans, etc. BETA
// SOFTWARE, PROVIDED AS IS WITH NO WARRANTIES WHATSOEVER.

// Polygon mainnet version

library CronosPriceGetter {
    using AMMData for AmmData;
    
    //Returned prices calculated with this precision (18 decimals)
    uint public constant DECIMALS = 18;
    uint private constant PRECISION = 1e18; //1e18 == $1
    
    //Token addresses
    address constant WCRO = 0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23; //18 decimals
    address constant WETH = 0xe44Fd7fCb2b1581822D0c862B68222998a0c299a; //18 decimals
    address constant WBTC = 0x062E66477Faf219F25D27dCED647BF57C3107d52; //8 decimals
    address constant USDC = 0xc21223249CA28397B4B6541dfFaEcC539BfF0c59; //6 decimals
    address constant DAI = 0xF2001B145b43032AAF5Ee2884e456CCd805F677D; //18 decimals
    address constant USDT = 0x66e428c3f67a68878562e79A0234c1F83c208770; //6 decimals

    // Crodex LP addresses
    address private constant WCRO_USDT_PAIR = 0x47AB43F8176696CA569b14A24621A46b318096A7;
    address private constant WCRO_DAI_PAIR = 0x586e3658d0299d5e79B53aA51B641d6A0B8A4Dd3;
    address private constant WCRO_USDC_PAIR = 0x182414159C3eeF1435aF91Bcf0d12AbcBe277A46;
    
    address private constant WETH_USDT_PAIR = 0xc061A750B252f36337e960BbC2A7dB96b3Bc7906;
    address private constant USDC_WETH_PAIR = 0x50BEAbE48641D324DB5a1d0EF0e882Db22AE1a75; 
    address private constant WETH_DAI_PAIR = 0x5515094dB1a1B9487955ABe0744ACaa2fa1451F3; 

    // Normalized to specified number of decimals based on token's decimals and
    // specified number of decimals
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
        
        return getRawPrice(token, getCROPrice(), getETHPrice());
    }
    
    //returns the prices of multiple tokens, zero on failure
    function getRawPrices(address[] calldata tokens) public view returns (uint[] memory prices) {
        prices = new uint[](tokens.length);
        uint croPrice = getCROPrice();
        uint ethPrice = getETHPrice();
        
        for (uint i; i < prices.length; i++) {
            address token = tokens[i];
            
            uint pegPrice = pegTokenPrice(token, croPrice, ethPrice);
            if (pegPrice != 0) prices[i] = pegPrice;
            else prices[i] = getRawPrice(token, croPrice, ethPrice);
        }
    }
    
    //returns the value of a LP token if it is one, or the regular price if it isn't LP
    function getRawLPPrice(address token) internal view returns (uint) {
        uint pegPrice = pegTokenPrice(token);
        if (pegPrice != 0) return pegPrice;
        
        return getRawLPPrice(token, getCROPrice(), getETHPrice());
    }
    //returns the prices of multiple tokens which may or may not be LPs
    function getRawLPPrices(address[] calldata tokens) internal view returns (uint[] memory prices) {
        prices = new uint[](tokens.length);
        uint croPrice = getCROPrice();
        uint ethPrice = getETHPrice();
        
        for (uint i; i < prices.length; i++) {
            address token = tokens[i];
            
            uint pegPrice = pegTokenPrice(token, croPrice, ethPrice);
            if (pegPrice != 0) prices[i] = pegPrice;
            else prices[i] = getRawLPPrice(token, croPrice, ethPrice);
        }
    }
    //returns the current USD price of CRO based on primary stablecoin pairs
    function getCROPrice() internal view returns (uint) {
        (uint wcroReserve0, uint usdtReserve,) = IUniswapV2Pair(WCRO_USDT_PAIR).getReserves();
        (uint wcroReserve1, uint daiReserve,) = IUniswapV2Pair(WCRO_DAI_PAIR).getReserves();
        (uint wcroReserve2, uint usdcReserve,) = IUniswapV2Pair(WCRO_USDC_PAIR).getReserves();
        uint wcroTotal = wcroReserve0 + wcroReserve1 + wcroReserve2;
        uint usdTotal = daiReserve + (usdcReserve + usdtReserve)*1e12; // 1e18 USDC/T == 1e30 DAI
        
        return usdTotal * PRECISION / wcroTotal; 
    }
    
    // //returns the current USD price of CRO based on primary stablecoin pairs
    function getETHPrice() internal view returns (uint) {
        (uint usdtReserve, uint wethReserve0,) = IUniswapV2Pair(WETH_USDT_PAIR).getReserves();
        (uint usdcReserve, uint wethReserve1,) = IUniswapV2Pair(USDC_WETH_PAIR).getReserves();
        (uint wethReserve2, uint daiReserve,) = IUniswapV2Pair(WETH_DAI_PAIR).getReserves();
        uint wethTotal = wethReserve0; //+ wethReserve1 + wethReserve2;
        uint usdTotal = usdtReserve*1e12; //daiReserve + (usdcReserve + usdtReserve)*1e12 //1e18 USDC/T == 1e30 DAI
        
        return usdTotal * PRECISION / wethTotal; 
    }
    
    //Calculate LP token value in USD. Generally compatible with any UniswapV2 pair but will always price underlying
    //tokens using Crodex prices. If the provided token is not a LP, it will attempt to price the token as a
    //standard token. This is useful for MasterChef farms which stake both single tokens and pairs
    function getRawLPPrice(address lp, uint croPrice, uint ethPrice) internal view returns (uint) {
        
        //if not a LP, handle as a standard token
        try IUniswapV2Pair(lp).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            
            address token0 = IUniswapV2Pair(lp).token0();
            address token1 = IUniswapV2Pair(lp).token1();
            uint totalSupply = IUniswapV2Pair(lp).totalSupply();
            
            //price0*reserve0+price1*reserve1
            uint totalValue = getRawPrice(token0, croPrice, ethPrice) * reserve0 
                + getRawPrice(token1, croPrice, ethPrice) * reserve1;
            
            return totalValue / totalSupply;
            
        } catch {
            return getRawPrice(lp, croPrice, ethPrice);
        }
    }

    // checks for primary tokens and returns the correct predetermined price if possible, otherwise calculates price
    function getRawPrice(address token, uint croPrice, uint ethPrice) internal view returns (uint rawPrice) {
        uint pegPrice = pegTokenPrice(token, croPrice, ethPrice);
        if (pegPrice != 0) return pegPrice;

        uint numTokens;
        uint pairedValue;
        
        uint lpTokens;
        uint lpValue;
        
        (lpTokens, lpValue) = pairTokensAndValueMulti(token, WCRO);
        numTokens += lpTokens;
        pairedValue += lpValue;
        
        (lpTokens, lpValue) = pairTokensAndValueMulti(token, WETH);
        numTokens += lpTokens;
        pairedValue += lpValue;
        
        (lpTokens, lpValue) = pairTokensAndValueMulti(token, DAI);
        numTokens += lpTokens;
        pairedValue += lpValue;
        
        (lpTokens, lpValue) = pairTokensAndValueMulti(token, USDC);
        numTokens += lpTokens;
        pairedValue += lpValue;
        
        (lpTokens, lpValue) = pairTokensAndValueMulti(token, USDT);
        numTokens += lpTokens;
        pairedValue += lpValue;
        
        if (numTokens > 0) return pairedValue / numTokens;
    }
    //if one of the peg tokens, returns that price, otherwise zero
    function pegTokenPrice(address token, uint croPrice, uint ethPrice) private pure returns (uint) {
        if (token == USDT || token == USDC) return PRECISION*1e12;
        if (token == WCRO) return croPrice;
        if (token == WETH) return ethPrice;
        if (token == DAI) return PRECISION;
        return 0;
    }
    function pegTokenPrice(address token) private view returns (uint) {
        if (token == USDT || token == USDC) return PRECISION*1e12;
        if (token == WCRO) return getCROPrice();
        if (token == WETH) return getETHPrice();
        if (token == DAI) return PRECISION;
        return 0;
    }

    //returns the number of tokens and the USD value within a single LP. peg is one of the listed primary, pegPrice is the predetermined USD value of this token
    function pairTokensAndValue(address token, address peg, address factory, bytes32 initcodehash) private view returns (uint tokenNum, uint pegValue) {

        address tokenPegPair = pairFor(token, peg, factory, initcodehash);
        
        // if the address has no contract deployed, the pair doesn't exist
        uint256 size;
        assembly { size := extcodesize(tokenPegPair) }
        if (size == 0) return (0,0);
        
        try IUniswapV2Pair(tokenPegPair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            uint reservePeg;
            (tokenNum, reservePeg) = token < peg ? (reserve0, reserve1) : (reserve1, reserve0);
            pegValue = reservePeg * pegTokenPrice(peg);
        } catch {
            return (0,0);
        }

    }
    
    function pairTokensAndValueMulti(address token, address peg) private view returns (uint tokenNum, uint pegValue) {
        
        //across all AMMs in AMMData library
        for (AmmData amm = AmmData.CRODEX; uint8(amm) < AMMData.NUM_AMMS; amm = AmmData(uint(amm) + 1)) {
            (uint tokenNumLocal, uint pegValueLocal) = pairTokensAndValue(token, peg, amm.factory(), amm.pairCodeHash());
            tokenNum += tokenNumLocal;
            pegValue += pegValueLocal;
        }
    }
    
    //normalize a token price to a specified number of decimals
    function normalize(uint price, address token, uint _decimals) private view returns (uint) {
        uint tokenDecimals;
        
        try IERC20Metadata(token).decimals() returns (uint8 dec) {
            tokenDecimals = dec;
        } catch {
            tokenDecimals = 18;
        }

        if (tokenDecimals + _decimals <= 2*DECIMALS) return price / 10**(2*DECIMALS - tokenDecimals - _decimals);
        else return price * 10**(_decimals + tokenDecimals - 2*DECIMALS);
    
    }
    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB, address factory, bytes32 initcodehash) private pure returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                initcodehash
        )))));
    }
    
    
}