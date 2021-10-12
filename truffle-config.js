const HDWalletProvider = require('@truffle/hdwallet-provider');
require('dotenv').config();

 //const POLYGON_DEPLOYER_KEY = process.env.POLYGON_DEPLOYER_KEY;
const MY_PRIVATE_KEY = process.env.MY_PRIVATE_KEY;
const PRIVATE_RPC = process.env.PRIVATE_RPC;

module.exports = {
  networks: {
    polygon: {
      provider: () => new HDWalletProvider(MY_PRIVATE_KEY, PRIVATE_RPC),
      //provider: () => new HDWalletProvider(POLYGON_DEPLOYER_KEY, `https://matic-mainnet.chainstacklabs.com`),
      //provider: () => new HDWalletProvider(POLYGON_DEPLOYER_KEY, `https://rpc-mainnet.matic.network`),
      network_id: 137,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
      gasPrice: 30000000000
    },
  },
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys: {
    polygonscan: process.env.POLYGONSCAN_API_KEY
  },
  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.4",    // Fetch exact version from solc-bin (default: truffle's version)
      settings: {          // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 200
        },
      }
    },
  }
}
