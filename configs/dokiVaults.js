const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { WMATIC, DAI, CRYSTL, AZUKI, MUST, DOKI, WETH, USDC  } = tokens.polygon;

const dokiVaults = [
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.DOKI_STAKING_REWARDS_AZUKI_MUST, // Masterchef
            routers.polygon.COMETH_ROUTER, // UniRouter
            lps.polygon.AZUKI_MUST_COMETH_LP, // Want
            MUST, // Earned - there is a second reward in AZUKI!
            AZUKI, //EarnedBeta
        ],
        strategyConfig: [
            999, //pid
            1, // uint256 tolerance
            [MUST, WMATIC], // address[] memory _earnedToWmaticPath
            [MUST, USDC, DAI], // address[] memory _earnedToUsdcPath
            [MUST, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [MUST, AZUKI], // address[] memory _earnedToToken0Path
            [MUST], // address[] memory _earnedToToken1Path
            [AZUKI, MUST], // address[] memory _token0ToEarnedPath
            [MUST], // address[] memory _token1ToEarnedPath
            [AZUKI, MUST] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.DOKI_STAKING_REWARDS_AZUKI_ETH, // Masterchef
            routers.polygon.COMETH_ROUTER, // UniRouter
            lps.polygon.AZUKI_ETH_COMETH_LP, // Want
            MUST, // Earned - there is a second reward in AZUKI!
            AZUKI, //EarnedBeta
        ],
        strategyConfig: [
            999, //pid
            1, // uint256 tolerance
            [MUST, WMATIC], // address[] memory _earnedToWmaticPath
            [MUST, USDC, DAI], // address[] memory _earnedToUsdcPath
            [MUST, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [MUST, AZUKI], // address[] memory _earnedToToken0Path
            [MUST, WETH], // address[] memory _earnedToToken1Path
            [AZUKI, MUST], // address[] memory _token0ToEarnedPath
            [WETH, MUST], // address[] memory _token1ToEarnedPath
            [AZUKI, MUST] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.DOKI_STAKING_REWARDS_DOKI_MUST, // Masterchef
            routers.polygon.COMETH_ROUTER, // UniRouter
            lps.polygon.DOKI_MUST_COMETH_LP, // Want
            MUST, // Earned - there is a second reward in AZUKI!
            AZUKI, //EarnedBeta
        ],
        strategyConfig: [
            999, //pid
            1, // uint256 tolerance
            [MUST, WMATIC], // address[] memory _earnedToWmaticPath
            [MUST, USDC, DAI], // address[] memory _earnedToUsdcPath
            [MUST, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [MUST, DOKI], // address[] memory _earnedToToken0Path
            [MUST], // address[] memory _earnedToToken1Path
            [DOKI, MUST], // address[] memory _token0ToEarnedPath
            [MUST], // address[] memory _token1ToEarnedPath
            [AZUKI, MUST] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.DOKI_STAKING_REWARDS_DOKI_ETH, // Masterchef
            routers.polygon.COMETH_ROUTER, // UniRouter
            lps.polygon.DOKI_ETH_COMETH_LP, // Want
            MUST, // Earned - there is a second reward in AZUKI!
            AZUKI, //EarnedBeta
        ],
        strategyConfig: [
            999, //pid
            1, // uint256 tolerance
            [MUST, WMATIC], // address[] memory _earnedToWmaticPath
            [MUST, USDC, DAI], // address[] memory _earnedToUsdcPath
            [MUST, WMATIC, CRYSTL], // address[] memory _earnedToCrystlPath
            [MUST, DOKI], // address[] memory _earnedToToken0Path
            [MUST, WETH], // address[] memory _earnedToToken1Path
            [DOKI, MUST], // address[] memory _token0ToEarnedPath
            [WETH, MUST], // address[] memory _token1ToEarnedPath
            [AZUKI, MUST] // address[] memory _EarnedBetaToEarnedPath
        ],
    },
]

module.exports = {
    dokiVaults
}
