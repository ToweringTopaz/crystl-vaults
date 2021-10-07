const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { QUICK, WMATIC, CRYSTL, KOM, DAI } = tokens.polygon;

const quickVaults = [
    {
        addresses: [
            accounts.polygon.KINGD_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.QUICK_STAKING_REWARDS_QUICK_KOM_V2, // Masterchef
            routers.polygon.QUICKSWAP_ROUTER, // UniRouter
            lps.polygon.QUICK_KOM_QUICK_LP, // Want
            QUICK, // Earned
        ],
        strategyConfig: [
            999, // uint256 _pid 
            1, // uint256 tolerance
            [QUICK, WMATIC], // address[] memory _earnedToWmaticPath
            [QUICK, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [QUICK, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [QUICK], // address[] memory _earnedToToken0Path
            [QUICK, WMATIC, KOM], // address[] memory _earnedToToken1Path
            [QUICK], // address[] memory _token0ToEarnedPath
            [KOM, WMATIC, QUICK], // address[] memory _token1ToEarnedPath
        ]
    },
]

module.exports = {
    quickVaults
}
