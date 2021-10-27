const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { WCRO, CRX, USDC } = tokens.cronos_testnet;

const crodexVaults = [
    {
        addresses: [
            accounts.cronos_testnet.RICH_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.cronos_testnet.PHOTONSWAP_MASTERCHEF, // Masterchef
            routers.cronos_testnet.PHOTONSWAP_ROUTER, // UniRouter
            lps.cronos_testnet.WCRO_PHOTON_PHOTON_LP, // Want
            WCRO, // Earned 
        ],
        strategyConfig: [
            7, // uint256 _pid 
            1, // uint256 tolerance
            [WCRO], // address[] memory _earnedToWnativePath
            [WCRO, USDC], // address[] memory _earnedToUsdcPath
            [WCRO], // address[] memory _earnedToCrystlPath
            [WCRO], // address[] memory _earnedToToken0Path
            [WCRO, CRX], // address[] memory _earnedToToken1Path
            [WCRO], // address[] memory _token0ToEarnedPath
            [CRX, WCRO], // address[] memory _token1ToEarnedPath
        ],
    },
    
]

module.exports = {
    crodexVaults
}
