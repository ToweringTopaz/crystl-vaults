const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const {  WMATIC, DFYN  } = tokens.polygon;

const dfynVaults = [
    {
        want: lps.polygon.DFYN_WMATIC_DFYN_LP, // Want
        wantDust: 8,
        vaulthealer: accounts.polygon.PRODUCTION_VAULT_HEALER,
        masterchef: masterChefs.polygon.DFYN_STAKING_DFYN_WMATIC, // Masterchef
        router: routers.polygon.DFYN_ROUTER,
        PID: 999,
        earned: [ DFYN, WMATIC ],
        earnedDust: [8, 8]
    }
]

module.exports = {
    dfynVaults
}