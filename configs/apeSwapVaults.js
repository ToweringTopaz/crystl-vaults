const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { BANANA, WMATIC, CRYSTL, DAI } = tokens.polygon;
const { ZERO_ADDRESS } = accounts.polygon;

const apeSwapVaults = [
    {
        want: lps.polygon.MATIC_CRYSTL_APE_LP, // Want
        vaulthealer: accounts.polygon.NEW_TEST_VAULT_HEALER,
        masterchef: masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
		tactic: '0x6873808DBc09Aa85A3ebB996Adf91c41AeD4aCbf', //TacticMiniApe
        PID: 7,
        earned: [ BANANA, CRYSTL ],
    },
    {
		masterchef: masterChefs.polygon.APESWAP_MINICHEF, // Masterchef
		tactic: '0x6873808DBc09Aa85A3ebB996Adf91c41AeD4aCbf', //TacticMiniApe
		vaulthealer: accounts.polygon.NEW_TEST_VAULT_HEALER,
		want: lps.polygon.MATIC_BANANA_APE_LP, // Want
        earned: [ BANANA, WMATIC ],
        paths: [], // all wmatic paths, so auto-gen
        PID: 0,
    },
]

module.exports = {
    apeSwapVaults
}
