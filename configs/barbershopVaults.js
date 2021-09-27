const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { HAIR, WMATIC, CRYSTL, DAI } = tokens.polygon;

const barbershopVaults = [
    {
        addresses: [
            accounts.polygon.NEW_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.BARBER_MASTERCHEF, // Masterchef
            routers.polygon.APESWAP_ROUTER, // UniRouter
            lps.polygon.MATIC_CRYSTL_APE_LP, // Want
            HAIR, // Earned
        ],
        strategyConfig: [
            9, // uint256 _pid 
            1, // uint256 tolerance
            [HAIR, WMATIC], // address[] memory _earnedToWmaticPath
            [HAIR, WMATIC, DAI], // address[] memory _earnedToUsdcPath
            [HAIR, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [HAIR, WMATIC], // address[] memory _earnedToToken0Path
            [HAIR, WMATIC, CRYSTL], // address[] memory _earnedToToken1Path
            [WMATIC, HAIR], // address[] memory _token0ToEarnedPath
            [CRYSTL, WMATIC, HAIR], // address[] memory _token1ToEarnedPath
        ]
    }
]

module.exports = {
    barbershopVaults
}
