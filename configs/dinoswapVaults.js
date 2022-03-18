const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { DINO } = tokens.polygon;

const dinoswapVaults = [
    {
        want: lps.polygon.WMATIC_WETH_DINOV2_LP, // Want
        wantDust: 8,
        vaulthealer: accounts.polygon.PRODUCTION_VAULT_HEALER,
        masterchef: masterChefs.polygon.DINOSWAP_MASTERCHEF, // Masterchef
        router: routers.polygon.DINO_ROUTER,
        PID: 29,
        earned: [ DINO ],
        earnedDust: [0],
    }
]

module.exports = {
    dinoswapVaults
}
