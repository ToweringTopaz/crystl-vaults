const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { BANANA, WMATIC, CRYSTL, DAI } = tokens.polygon;
const { ZERO_ADDRESS } = accounts.polygon;

const apeSwapVaults = [
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            routers.polygon.APESWAP_ROUTER, // UniRouter
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            accounts.polygon.FEE_ADDRESS, // rewardFee
            accounts.polygon.FEE_ADDRESS, // withdrawFee
            accounts.polygon.BURN_ADDRESS, // 0xdead
            lps.polygon.MATIC_CRYSTL_APE_LP, // Want
            [ BANANA, CRYSTL, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS ],
            [ ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS ]
        ],
        paths: [
            [BANANA, WMATIC], //  earned to wmatic, earned to token0
            [BANANA, WMATIC, DAI], // earned to dai
            [BANANA, WMATIC, CRYSTL], // earned to crystl, earned to token1
            [CRYSTL, WMATIC], // earned2 to wmatic, earned2 to token0
            [CRYSTL, WMATIC, DAI], // earned2 to dai
            [CRYSTL] // earned2 to crystl, earned2 to token1
        ],
        PID: 8,
    },
    {
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            routers.polygon.APESWAP_ROUTER, // UniRouter
            masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
            accounts.polygon.FEE_ADDRESS, // rewardFee
            accounts.polygon.FEE_ADDRESS, // withdrawFee
            accounts.polygon.BURN_ADDRESS, // 0xdead
            lps.polygon.MATIC_BANANA_APE_LP, // Want
            [ BANANA, WMATIC, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS ],
            [ ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS ]
        ],
        paths: [
            [BANANA, WMATIC], //  earned to wmatic, earned to token0
            [BANANA, WMATIC, DAI], // earned to dai
            [BANANA, WMATIC, CRYSTL], // earned to crystl
            [BANANA], // earned to token1
            [WMATIC], // earned2 to wmatic, earned2 to token0
            [WMATIC, DAI], // earned2 to dai
            [WMATIC, CRYSTL], //earned2 to crystl
            [WMATIC, BANANA] //earned2 to token1
        ],
        PID: 8,
    },
]

module.exports = {
    apeSwapVaults
}
