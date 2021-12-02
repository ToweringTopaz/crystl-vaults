const { accounts, tokens, masterChefs, tactics } = require('./addresses.js');
const { CRYSTL } = tokens.polygon;

const crystlVault = [
    {
        want: CRYSTL, // Want
        vaulthealer: accounts.polygon.NEW_TEST_VAULT_HEALER,
        masterchef: masterChefs.polygon.CRYSTL_MASTERHEALER, // MasterHealer
		tactic: tactics.polygon.TACTIC_MASTERHEALER, //TacticMasterHealer
        PID: 0,
        earned: [ CRYSTL ],
    },
]

module.exports = {
    crystlVault
}
