const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { BANANA, WMATIC, CRYSTL, DAI } = tokens.polygon;
const { ZERO_ADDRESS } = accounts.polygon;

const apeSwapVaults = [
    {
        want: lps.polygon.MATIC_CRYSTL_APE_LP, // Want
        vaulthealer: accounts.polygon.NEW_TEST_VAULT_HEALER,
        masterchef: masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
        PID: 7,
        earned: [ BANANA, CRYSTL ],
    },
    {
        want: lps.polygon.MATIC_BANANA_APE_LP, // Want
        vaulthealer: accounts.polygon.NEW_TEST_VAULT_HEALER,
        masterchef: masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
        PID: 0,
        earned: [ BANANA, WMATIC ],
    },
]

module.exports = {
    apeSwapVaults
}
