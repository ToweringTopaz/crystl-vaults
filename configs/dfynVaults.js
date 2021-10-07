const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { DFYN, WMATIC, WMATIC_DFYN, CRYSTL, DAI, FRM, WETH, ROUTE } = tokens.polygon;

const dfynVaults = [
    {
        addresses: [
            accounts.polygon.NEW_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.DFYN_STAKING_REWARDS_FRM_DFYN, // Masterchef
            routers.polygon.DFYN_ROUTER, // UniRouter
            lps.polygon.DFYN_FRM_DFYN_LP, // Want
            DFYN, // Earned
        ],
        strategyConfig: [
            999, // uint256 _pid 
            1, // uint256 tolerance
            [DFYN, WMATIC], // address[] memory _earnedToWmaticPath
            [DFYN, WMATIC_DFYN, DAI], // address[] memory _earnedToUsdcPath
            [DFYN, WMATIC_DFYN, CRYSTL], // address[] memory _earnedToCrystlPath
            [DFYN], // address[] memory _earnedToToken0Path
            [DFYN, ROUTE, WETH, FRM], // address[] memory _earnedToToken1Path
            [DFYN], // address[] memory _token0ToEarnedPath
            [FRM, WETH, ROUTE, DFYN], // address[] memory _token1ToEarnedPath
        ]
    },
]

module.exports = {
    dfynVaults
}
