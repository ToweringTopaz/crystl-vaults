const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { BANANA, WMATIC, CRYSTL, DAI, CRO } = tokens.cronos;

const crodexVaults = [
    {
        addresses: [
            accounts.cronos.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.cronos.APESWAP_MINICHEF, // Masterchef
            routers.cronos.APESWAP_ROUTER, // UniRouter
            lps.cronos.MATIC_CRYSTL_APE_LP, // Want
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
    
]

module.exports = {
    crodexVaults
}
