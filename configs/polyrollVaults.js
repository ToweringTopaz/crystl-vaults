const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { WMATIC, ROLL, DAI } = tokens.polygon;

const polyrollVaults = [
    {
        addresses: [
            accounts.polygon.NEW_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.POLYROLL_MASTERCHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_ROLL_APE_LP, // Want
            ROLL, // Earned
        ],
        strategyConfig: [
            8, // uint256 _pid 
            1, // uint256 tolerance
            [ROLL, WMATIC], // address[] memory _earnedToWmaticPath
            [ROLL, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [ROLL, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [ROLL, WMATIC], // address[] memory _earnedToToken0Path
            [ROLL], // address[] memory _earnedToToken1Path
            [WMATIC, ROLL], // address[] memory _token0ToEarnedPath
            [ROLL], // address[] memory _token1ToEarnedPath
        ]
    },
]

module.exports = {
    polyrollVaults
}
