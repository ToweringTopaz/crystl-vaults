const { accounts, tokens, masterChefs, lps } = require('./addresses.js');
const { QUICK } = tokens.polygon;

const quickVaults = [
    {
        want: lps.polygon.QUICK_KOM_QUICK_LP, // Want
        vaulthealer: accounts.polygon.PRODUCTION_VAULT_HEALER,
        masterchef: masterChefs.polygon.QUICK_MASTERCHEF, // Masterchef
        PID: 0,
        earned: [ QUICK ],
    },
]

module.exports = {
    quickVaults
}
