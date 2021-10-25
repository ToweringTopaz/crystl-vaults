const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { BANANA, WMATIC, CRYSTL, DAI, BNB, USDC, WBTC, USDT, WETH } = tokens.polygon;

const apeSwapVaults = [
    {
        addresses: [ //0
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_CRYSTL_APE_LP, // Want
            CRYSTL, // Earned 
            BANANA, //EarnedBeta
        ],
        strategyConfig: [
            7, // uint256 _pid 
            1, // uint256 tolerance
            [CRYSTL, WMATIC], // address[] memory _earnedToWmaticPath
            [CRYSTL, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [CRYSTL], // address[] memory _earnedToCrystlPath
            [CRYSTL, WMATIC], // address[] memory _earnedToToken0Path
            [CRYSTL], // address[] memory _earnedToToken1Path
            [WMATIC, CRYSTL], // address[] memory _token0ToEarnedPath
            [CRYSTL], // address[] memory _token1ToEarnedPath
            [BANANA, WMATIC, CRYSTL] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [ //1
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_BANANA_APE_LP, // Want
            WMATIC, // Earned
            BANANA, //EarnedBeta
        ],
        strategyConfig: [
            0, // uint256 _pid 
            1, // uint256 tolerance
            [WMATIC], // address[] memory _earnedToWmaticPath
            [WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [WMATIC], // address[] memory _earnedToToken0Path
            [WMATIC, BANANA], // address[] memory _earnedToToken1Path
            [WMATIC], // address[] memory _token0ToEarnedPath
            [BANANA, WMATIC], // address[] memory _token1ToEarnedPath
            [BANANA, WMATIC] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [ //2
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.WMATIC_BNB_APE_LP, // Want
            WMATIC, // Earned
            BANANA, //EarnedBeta
        ],
        strategyConfig: [
            6, // uint256 _pid 
            1, // uint256 tolerance
            [WMATIC], // address[] memory _earnedToWmaticPath
            [WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [WMATIC], // address[] memory _earnedToToken0Path
            [WMATIC, BNB], // address[] memory _earnedToToken1Path
            [WMATIC], // address[] memory _token0ToEarnedPath
            [BNB, WMATIC], // address[] memory _token1ToEarnedPath
            [BANANA, WMATIC] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [ //3
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.USDC_DAI_APE_LP, // Want
            WMATIC, // Earned
            BANANA, //EarnedBeta
        ],
        strategyConfig: [
            5, // uint256 _pid 
            1, // uint256 tolerance
            [WMATIC], // address[] memory _earnedToWmaticPath
            [WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [WMATIC, USDC], // address[] memory _earnedToToken0Path
            [WMATIC, DAI], // address[] memory _earnedToToken1Path
            [USDC, WMATIC], // address[] memory _token0ToEarnedPath
            [DAI, WMATIC], // address[] memory _token1ToEarnedPath
            [BANANA, WMATIC] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [ //4
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.WMATIC_WBTC_APE_LP, // Want
            WMATIC, // Earned
            BANANA, //EarnedBeta
        ],
        strategyConfig: [
            4, // uint256 _pid 
            1, // uint256 tolerance
            [WMATIC], // address[] memory _earnedToWmaticPath
            [WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [WMATIC], // address[] memory _earnedToToken0Path
            [WMATIC, WBTC], // address[] memory _earnedToToken1Path
            [WMATIC], // address[] memory _token0ToEarnedPath
            [WBTC, WMATIC], // address[] memory _token1ToEarnedPath
            [BANANA, WMATIC] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [ //5
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.WMATIC_WETH_APE_LP, // Want
            WMATIC, // Earned
            BANANA, //EarnedBeta
        ],
        strategyConfig: [
            1, // uint256 _pid 
            1, // uint256 tolerance
            [WMATIC], // address[] memory _earnedToWmaticPath
            [WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [WMATIC], // address[] memory _earnedToToken0Path
            [WMATIC, WETH], // address[] memory _earnedToToken1Path
            [WMATIC], // address[] memory _token0ToEarnedPath
            [WETH, WMATIC], // address[] memory _token1ToEarnedPath
            [BANANA, WMATIC] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [ //6
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.WMATIC_USDT_APE_LP, // Want
            WMATIC, // Earned
            BANANA, //EarnedBeta
        ],
        strategyConfig: [
            3, // uint256 _pid 
            1, // uint256 tolerance
            [WMATIC], // address[] memory _earnedToWmaticPath
            [WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [WMATIC], // address[] memory _earnedToToken0Path
            [WMATIC, USDT], // address[] memory _earnedToToken1Path
            [WMATIC], // address[] memory _token0ToEarnedPath
            [USDT, WMATIC], // address[] memory _token1ToEarnedPath
            [BANANA, WMATIC] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [ //7
            accounts.polygon.NEW_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.WMATIC_DAI_APE_LP, // Want
            WMATIC, // Earned
            BANANA, //EarnedBeta
        ],
        strategyConfig: [
            2, // uint256 _pid 
            1, // uint256 tolerance
            [WMATIC], // address[] memory _earnedToWmaticPath
            [WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [WMATIC], // address[] memory _earnedToToken0Path
            [WMATIC, DAI], // address[] memory _earnedToToken1Path
            [WMATIC], // address[] memory _token0ToEarnedPath
            [DAI, WMATIC], // address[] memory _token1ToEarnedPath
            [BANANA, WMATIC] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
]

module.exports = {
    apeSwapVaults
}
