const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { TAKO, WMATIC, CRYSTL, BANANA, WETH, INKU, DAI } = tokens.polygon;

const takoDefiVaults = [
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.TAKO_MASTERCHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_CRYSTL_APE_LP, // Want
            TAKO, // Earned
        ],
        strategyConfig: [
            5, // uint256 _pid 
            1, // uint256 tolerance
            [TAKO, WMATIC], // address[] memory _earnedToWmaticPath
            [TAKO, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [TAKO, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [TAKO, WMATIC], // address[] memory _earnedToToken0Path
            [TAKO, WMATIC, CRYSTL], // address[] memory _earnedToToken1Path
            [WMATIC, TAKO], // address[] memory _token0ToEarnedPath
            [CRYSTL, WMATIC, TAKO], // address[] memory _token1ToEarnedPath
        ]
    },
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.TAKO_MASTERCHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_TAKO_APE_LP, // Want
            TAKO, // Earned
        ],
        strategyConfig: [
            0, // uint256 _pid 
            1, // uint256 tolerance
            [TAKO, WMATIC], // address[] memory _earnedToWmaticPath
            [TAKO, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [TAKO, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [TAKO, WMATIC], // address[] memory _earnedToToken0Path
            [TAKO], // address[] memory _earnedToToken1Path
            [WMATIC, TAKO], // address[] memory _token0ToEarnedPath
            [TAKO], // address[] memory _token1ToEarnedPath
        ]
    },
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.TAKO_MASTERCHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_INKU_APE_LP, // Want
            TAKO, // Earned
        ],
        strategyConfig: [
            6, // uint256 _pid 
            1, // uint256 tolerance
            [TAKO, WMATIC], // address[] memory _earnedToWmaticPath
            [TAKO, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [TAKO, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [TAKO, WMATIC], // address[] memory _earnedToToken0Path
            [TAKO, WMATIC, INKU], // address[] memory _earnedToToken1Path
            [WMATIC, TAKO], // address[] memory _token0ToEarnedPath
            [INKU, WMATIC, TAKO], // address[] memory _token1ToEarnedPath
        ]
    },
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.TAKO_MASTERCHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.BANANA_ETH_APE_LP, // Want
            TAKO, // Earned
        ],
        strategyConfig: [
            4, // uint256 _pid 
            1, // uint256 tolerance
            [TAKO, WMATIC], // address[] memory _earnedToWmaticPath
            [TAKO, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [TAKO, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [TAKO, WMATIC, BANANA], // address[] memory _earnedToToken0Path
            [TAKO, WMATIC, WETH], // address[] memory _earnedToToken1Path
            [BANANA, WMATIC, TAKO], // address[] memory _token0ToEarnedPath
            [WETH, WMATIC, TAKO], // address[] memory _token1ToEarnedPath
        ]
    }
]

module.exports = {
    takoDefiVaults
}
