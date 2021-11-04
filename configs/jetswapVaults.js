const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { WMATIC, DAI, CRYSTL, WBTC, PWINGS, WETH, USDC  } = tokens.polygon;

const jetswapVaults = [
    {
        addresses: [
            accounts.polygon.KINGD_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.JETSWAP_MASTERCHEF, // Masterchef
            routers.polygon.JETSWAP_ROUTER, // UniRouter
            lps.polygon.WBTC_WETH_JET_LP, // Want
            accounts.polygon.FEE_ADDRESS, //rewardAddress & withdrawFeeAddress
            accounts.polygon.BUYBACK_ADDRESS,
            CRYSTL, //would usually be CRYSTL - replace with what in CRONOS?? WCRO for now...
            WMATIC, //WNATIVE
            PWINGS, // Earned
        ],
        strategyConfig: [
            14, //pid
            1, // uint256 tolerance
            [PWINGS, WMATIC], // address[] memory _earnedToWmaticPath
            [PWINGS, WMATIC, USDC, DAI], // address[] memory _earnedToUsdcPath
            [PWINGS, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [PWINGS, WMATIC, WETH, WBTC], // address[] memory _earnedToToken0Path
            [PWINGS, WMATIC, USDC, WETH], // address[] memory _earnedToToken1Path
            [WBTC, WETH, USDC, PWINGS], // address[] memory _token0ToEarnedPath
            [WETH, WMATIC, PWINGS], // address[] memory _token1ToEarnedPath
        ],
    },
   
]

module.exports = {
    jetswapVaults
}
