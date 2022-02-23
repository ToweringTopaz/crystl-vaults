const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { DINO, WMATIC, CRYSTL, DAI, USDC, WETH } = tokens.polygon;

const dinoswapVaults = [
    {
        addresses: [
            accounts.polygon.NEW_TEST_VAULT_HEALER, // Vault Healer
            masterChefs.polygon.DINOSWAP_MASTERCHEF, // Masterchef
            routers.polygon.DINO_ROUTER, // UniRouter
            lps.polygon.WMATIC_WETH_DINOV2_LP, // Want
            DINO, // Earned
            29, // uint256 _pid 
        ],
    }
]

module.exports = {
    dinoswapVaults
}
