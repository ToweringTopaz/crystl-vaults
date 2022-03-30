const HDWalletProvider = require('@truffle/hdwallet-provider');
require('dotenv').config();

 //const POLYGON_DEPLOYER_KEY = process.env.POLYGON_DEPLOYER_KEY;
const MY_PRIVATE_KEY = process.env.MY_PRIVATE_KEY;
const PRIVATE_RPC = process.env.PRIVATE_RPC;
const SPEEDY_RPC = process.env.SPEEDY_RPC;
const POLYGON_PUBLIC_RPC = process.env.POLYGON_PUBLIC_RPC;

module.exports = {
  networks: {
    polygon: {
      provider: () => new HDWalletProvider(MY_PRIVATE_KEY, POLYGON_PUBLIC_RPC),
      //provider: () => new HDWalletProvider(POLYGON_DEPLOYER_KEY, `https://matic-mainnet.chainstacklabs.com`),
      //provider: () => new HDWalletProvider(POLYGON_DEPLOYER_KEY, `https://rpc-mainnet.matic.network`),
      network_id: 137,
      networkCheckTimeout: 100000000,
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
      // gasPrice: 250000000000
    },
  },
  plugins: [
    'truffle-plugin-verify',
    'truffle-plugin-stdjsonin'
  ],
  
  api_keys: {
    polygonscan: process.env.POLYGONSCAN_API_KEY
  },
  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.13",    // Fetch exact version from solc-bin (default: truffle's version)
      settings: {          // See the solidity docs for advice about optimization and evmVersion
	    viaIR: true,
        optimizer: {
          enabled: true,
          runs: 200
        },
      }
    },
  }
}
