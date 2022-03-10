const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { BANANA, WMATIC, CRYSTL, DAI } = tokens.polygon;
const { ZERO_ADDRESS } = accounts.polygon;

const aaveVaults = [
    {
        want: tokens.polygon.USDC, // Want
        vaulthealer: accounts.polygon.NEW_TEST_VAULT_HEALER,
        masterchef: masterChefs.polygon.AAVE_LENDING_POOL, // Masterchef
        router: routers.polygon.APESWAP_ROUTER, //what does router do?
        PID: 7,
        earned: [ WMATIC ],
    },
]

module.exports = {
    aaveVaults
}
