/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@nomiclabs/hardhat-waffle');
require('dotenv').config()
require("solidity-coverage");

const chainIds = {
  hardhat: 31337,
};
/////////////////////////////////////////////////////////////////
/// Ensure that we have all the environment variables we need.///
/////////////////////////////////////////////////////////////////

// Ensure that we have mnemonic phrase set as an environment variable
const mnemonic = process.env.MNEMONIC;
if (!mnemonic) {
  throw new Error("Please set your MNEMONIC in a .env file");
}
// Ensure that we have archive mainnet node URL set as an environment variable
const archiveMainnetNodeURL = process.env.SPEEDY_ARCHIVE_RPC;
if (!archiveMainnetNodeURL) {
  throw new Error("Please set your PRIVATE_RPC in a .env file");
}

const myPrivateKey = process.env.MY_PRIVATE_KEY;
if (!myPrivateKey) {
  throw new Error("Please set your MY_PRIVATE_KEY in a .env file");
}

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      initialBaseFeePerGas: 1_00_000_000,
      gasPrice: "auto",
      allowUnlimitedContractSize: true,
      accounts: {
        initialIndex: 0,
        count: 20,
        mnemonic,
        path: "m/44'/60'/0'/0",
        accountsBalance: "10000000000000000000000",
      },
      forking: {
        url: archiveMainnetNodeURL,
        blockNumber: 23262000,
      },
      chainId: chainIds.hardhat,
      hardfork: "london",
    },
    polygon: {
      url: archiveMainnetNodeURL,
      accounts: [`0x${myPrivateKey}`], //do I really need to put my private key in here?
    },
  },
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
	  debug: {
	  }
    },
  },
  mocha: {
    timeout: 90000,
  },
};


