const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const {  WMATIC, DFYN  } = tokens.polygon;

const dfynVaults = [
    {
        want: lps.polygon.DFYN_WMATIC_DFYN_LP, // Want
        vaulthealer: accounts.polygon.PRODUCTION_VAULT_HEALER,
        masterchef: masterChefs.polygon.DFYN_STAKING_DFYN_WMATIC, // Masterchef
        PID: 999,
        earned: [ DFYN, WMATIC ]
    }
]

module.exports = {
    dfynVaults
}