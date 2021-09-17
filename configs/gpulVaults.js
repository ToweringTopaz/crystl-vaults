const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { GPUL, WMATIC, CRYSTL, GBNT, DAI } = tokens.polygon;

const gpulVaults = [
    {
        addresses: [
            accounts.polygon.NEW_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.POLYPULSAR_GAMMA_MASTERCHEF, // Masterchef
            routers.polygon.POLYCAT_ROUTER, // UniRouter
            lps.polygon.MATIC_GPUL_CAT_LP, // Want
            GPUL, // Earned
        ],
        strategyConfig: [
            0, // uint256 _pid 
            10, // uint256 tolerance
            [GPUL, WMATIC], // address[] memory _earnedToWmaticPath
            [GPUL, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [GPUL, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [GPUL, WMATIC], // address[] memory _earnedToToken0Path
            [GPUL], // address[] memory _earnedToToken1Path
            [WMATIC, GPUL], // address[] memory _token0ToEarnedPath
            [GPUL], // address[] memory _token1ToEarnedPath
        ]
    },
    {
        addresses: [
            accounts.polygon.NEW_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.POLYPULSAR_GAMMA_MASTERCHEF, // Masterchef
            routers.polygon.POLYCAT_ROUTER, // UniRouter
            lps.polygon.MATIC_GBNT_CAT_LP, // Want
            GPUL, // Earned
        ],
        strategyConfig: [
            1, // uint256 _pid 
            10, // uint256 tolerance
            [GPUL, WMATIC], // address[] memory _earnedToWmaticPath
            [GPUL, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [GPUL, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [GPUL, WMATIC], // address[] memory _earnedToToken0Path
            [GPUL, WMATIC, GBNT], // address[] memory _earnedToToken1Path
            [WMATIC, GPUL], // address[] memory _token0ToEarnedPath
            [GBNT, WMATIC, GPUL], // address[] memory _token1ToEarnedPath
        ]
    },
    
]

module.exports = {
    gpulVaults
}
