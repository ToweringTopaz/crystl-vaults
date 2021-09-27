const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { DINO, WMATIC, CRYSTL, DAI, USDC, ETH, WETH, USDT, SX } = tokens.polygon;

const dinoswapVaults = [
    {
        addresses: [
            accounts.polygon.NEW_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.DINOSWAP_MASTERCHEF, // Masterchef
            routers.polygon.SUSHISWAP_ROUTER, // UniRouter
            lps.polygon.ETH_SX_SUSHI_LP, // Want
            DINO, // Earned
        ],
        strategyConfig: [
            4, // uint256 _pid 
            1, // uint256 tolerance
            [DINO, USDT, WMATIC], // address[] memory _earnedToWmaticPath
            [DINO, USDC, DAI], // address[] memory _earnedToUsdcPath
            [DINO, USDC, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [DINO, WETH], // address[] memory _earnedToToken0Path
            [DINO, WETH, SX], // address[] memory _earnedToToken1Path
            [WETH, DINO], // address[] memory _token0ToEarnedPath
            [SX, WETH, WMATIC, DINO], // address[] memory _token1ToEarnedPath
        ]
    }
]

module.exports = {
    dinoswapVaults
}
