const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { CRONA, USDC, WCRO } = tokens.cronos_testnet;

const cronaswapVaults = [
    {
        addresses: [
            accounts.cronos_testnet.RICH_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.cronos_testnet.CRONASWAP_MASTERCHEF, // Masterchef
            routers.cronos_testnet.CRONASWAP_ROUTER, // UniRouter
            lps.cronos_testnet.CRONA_CRO_CRONA_LP, // Want
            accounts.cronos_testnet.FEE_ADDRESS, //rewardAddress & withdrawFeeAddress
            accounts.cronos_testnet.BUYBACK_ADDRESS,
            WCRO, //would usually be CRYSTL - replace with what in CRONOS?? WCRO for now...
        ],
        strategyConfig: [
            1, // uint256 _pid 
            1, // uint256 tolerance
            [CRONA, WCRO], // address[] memory _earnedToWnativePath
            [CRONA, USDC], // address[] memory _earnedToUsdcPath
            [CRONA, WCRO], // address[] memory _earnedToCrystlPath
            [CRONA, WCRO], // address[] memory _earnedToToken0Path
            [CRONA], // address[] memory _earnedToToken1Path
            [WCRO, CRONA], // address[] memory _token0ToEarnedPath
            [CRONA], // address[] memory _token1ToEarnedPath
        ],
    },
    {
        addresses: [
            accounts.cronos_testnet.RICH_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.cronos_testnet.CRONASWAP_MASTERCHEF, // Masterchef
            routers.cronos_testnet.CRONASWAP_ROUTER, // UniRouter
            lps.cronos_testnet.USDC_CRO_CRONA_LP, // Want
            accounts.cronos_testnet.FEE_ADDRESS, //rewardAddress & withdrawFeeAddress
            accounts.cronos_testnet.BUYBACK_ADDRESS,
            WCRO, //would usually be CRYSTL - replace with what in CRONOS?? WCRO for now... 
        ],
        strategyConfig: [
            2, // uint256 _pid 
            1, // uint256 tolerance
            [CRONA, WCRO], // address[] memory _earnedToWnativePath
            [CRONA, USDC], // address[] memory _earnedToUsdcPath
            [CRONA, WCRO], // address[] memory _earnedToCrystlPath
            [CRONA, WCRO], // address[] memory _earnedToToken0Path
            [CRONA, USDC], // address[] memory _earnedToToken1Path
            [WCRO, CRONA], // address[] memory _token0ToEarnedPath
            [USDC, CRONA], // address[] memory _token1ToEarnedPath
        ],
    },
    
]

module.exports = {
    cronaswapVaults
}
