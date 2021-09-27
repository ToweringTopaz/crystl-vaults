const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { BANANA, WMATIC, CRYSTL, DAI } = tokens.polygon;

const apeSwapVaults = [
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_CRYSTL_APE_LP, // Want
            BANANA, // Earned - there is a second reward in CRYSTL!
            CRYSTL, //EarnedBeta
        ],
        strategyConfig: [
            7, // uint256 _pid 
            1, // uint256 tolerance            
        ],
        earnedPaths: [
            [BANANA, WMATIC], // address[] memory _earnedToWmaticPath
            [BANANA, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [BANANA, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [BANANA, WMATIC], // address[] memory _earnedToToken0Path
            [BANANA, WMATIC, CRYSTL], // address[] memory _earnedToToken1Path
        ],
        earned2Paths: [
            [CRYSTL, WMATIC], // address[] memory _earnedToWmaticPath
            [CRYSTL, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [CRYSTL], // address[] memory _earnedToCrystlPath
            [CRYSTL, WMATIC], // address[] memory _earnedToToken0Path
            [CRYSTL], // address[] memory _earnedToToken1Path
        ],
    },
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_BANANA_APE_LP, // Want
            BANANA, // Earned
            CRYSTL, //EarnedBeta
        ],
        strategyConfig: [
            0, // uint256 _pid 
            1, // uint256 tolerance
            [BANANA, WMATIC], // address[] memory _earnedToWmaticPath
            [BANANA, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [BANANA, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [BANANA, WMATIC], // address[] memory _earnedToToken0Path
            [BANANA], // address[] memory _earnedToToken1Path
            [WMATIC, BANANA], // address[] memory _token0ToEarnedPath
            [BANANA], // address[] memory _token1ToEarnedPath
            [CRYSTL, WMATIC, BANANA] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
]

module.exports = {
    apeSwapVaults
}
