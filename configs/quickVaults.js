const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { QUICK, WMATIC, RELAY  } = tokens.polygon;

const quickVaults = [
    { 
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.QUICK_STAKING_RELAY_QUICK, // Masterchef
            routers.polygon.QUICKSWAP_ROUTER, // UniRouter
            lps.polygon.RELAY_QUICK_QUICK_LP, // Want
            QUICK, // Earned
        ],
        strategyConfig: [
            0, // uint256 _pid 
            1, // uint256 tolerance
            [QUICK, WMATIC], // address[] memory _earnedToWmaticPath
            [QUICK, WMATIC], // address[] memory _earnedToUsdcPath
            [QUICK, WMATIC], // address[] memory _earnedToCrystlPath
            [QUICK], // address[] memory _earnedToToken0Path
            [QUICK, RELAY], // address[] memory _earnedToToken1Path
            [QUICK], // address[] memory _token0ToEarnedPath
            [RELAY, QUICK], // address[] memory _token1ToEarnedPath
        ]
    },
]

module.exports = {
    quickVaults
}
