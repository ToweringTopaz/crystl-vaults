const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { QUICK } = tokens.polygon;

const quickVaults = [
    { 
        want: lps.polygon.RELAY_QUICK_QUICK_LP, // Want
        wantDust: 8,
        vaulthealer: accounts.polygon.PRODUCTION_VAULT_HEALER,
        masterchef: masterChefs.polygon.QUICK_STAKING_RELAY_QUICK, // Masterchef
        router: routers.polygon.QUICKSWAP_ROUTER,
        PID: 999,
        earned: [ QUICK ],
        earnedDust: [8]
    },
]

module.exports = {
    quickVaults
}
