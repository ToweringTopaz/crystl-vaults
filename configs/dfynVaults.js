const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const {  WMATIC, DFYN  } = tokens.polygon;

const dfynVaults = [

    { 
        addresses: [
            accounts.polygon.PRODUCTION_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.DFYN_STAKING_DFYN_WMATIC, // Masterchef
            routers.polygon.DFYN_ROUTER, // UniRouter
            lps.polygon.DFYN_WMATIC_DFYN_LP, // Want
            DFYN, WMATIC // Earned
            
        ]
    },
]