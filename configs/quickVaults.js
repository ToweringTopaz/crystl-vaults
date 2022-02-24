const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { QUICK } = tokens.polygon;

const quickVaults = [
    { 
        want: lps.polygon.RELAY_QUICK_QUICK_LP, // Want
        vaulthealer: accounts.polygon.PRODUCTION_VAULT_HEALER,
        masterchef: masterChefs.polygon.QUICK_STAKING_RELAY_QUICK, // Masterchef
        PID: 999,
        earned: [ QUICK ]
    },
]

module.exports = {
    quickVaults
}
