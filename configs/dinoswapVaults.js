const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { DINO } = tokens.polygon;

const dinoswapVaults = [
    {
        want: lps.polygon.ETH_SX_SUSHI_LP, // Want
        vaulthealer: accounts.polygon.NEW_TEST_VAULT_HEALER,
        masterchef: masterChefs.polygon.DINOSWAP_MASTERCHEF, // Masterchef
        PID: 4,
        earned: [ DINO ],
    }
]

module.exports = {
    dinoswapVaults
}
