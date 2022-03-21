/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@nomiclabs/hardhat-waffle');
require('dotenv').config()
require("solidity-coverage");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-solhint");

const { accounts } = require('./configs/addresses.js');
// const { ethers } = require('hardhat');
const { dfynVaults } = require('./configs/dfynVaults.js'); //<-- normal and maximizer vault(s)

const { tactics_abi } = require('./test/abi_files/tactics_abi.js');
const { strategyConfig_abi } = require('./test/abi_files/strategyConfig_abi.js');
const { vaultHealer_abi } = require('./test/abi_files/vaultHealer_abi.js');

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

const polygonScanApiKey = process.env.POLYGONSCAN_API_KEY;
if (!polygonScanApiKey) {
  throw new Error("Please set your POLYGONSCAN_API_KEY in a .env file");
}

task("createVault", "Creates a new vault")
  // .addParam("account", "The account's address")
  .setAction(async (taskArgs) => {
    tactics =  await ethers.getContractAt(tactics_abi, accounts.polygon.TACTICS);
    console.log("Tactics Instantiated")
    strategyConfig =  await ethers.getContractAt(strategyConfig_abi, accounts.polygon.STRATEGY_CONFIG);
    console.log("strategyConfig Instantiated")
    vaultHealer = await ethers.getContractAs(vaultHealer_abi, accounts.polygon.VAULTHEALER)
    console.log("vaultHealer Instantiated")

    let [tacticsA, tacticsB] = await tactics.generateTactics(
      dfynVaults[0]['masterchef'],
      dfynVaults[0]['PID'],
      0, //position of return value in vaultSharesTotal returnData array - have to look at contract and see
      ethers.BigNumber.from("0x70a0823130000000"), //vaultSharesTotal - includes selector and encoded call format
      ethers.BigNumber.from("0xa694fc3a40000000"), //deposit - includes selector and encoded call format
      ethers.BigNumber.from("0x2e1a7d4d40000000"), //withdraw - includes selector and encoded call format
      ethers.BigNumber.from("0x3d18b91200000000"), //harvest - includes selector and encoded call format
      ethers.BigNumber.from("0xe9fad8ee00000000") //emergency withdraw - includes selector and encoded call format
    );
    
    DEPLOYMENT_DATA = await strategyConfig.generateConfig(
      tacticsA,
      tacticsB,
      dfynVaults[0]['want'],
      dfynVaults[0]['wantDust'],
      dfynVaults[0]['router'], //note this has to be specified at deployment time
      accounts.polygon.V3_MAGNETITE, //where do we get this from?
      240, //slippageFactor
      false, //feeOnTransfer
      dfynVaults[0]['earned'],
      dfynVaults[0]['earnedDust'],
    );
    
    await vaultHealer.connect(vaultHealerOwnerSigner).createVault(strategyImplementation.address, DEPLOYMENT_DATA);
    
    strat_pid = await vaultHealer.numVaultsBase();
    
    console.log("New strategy pid: ", strat_pid);
  });

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      initialBaseFeePerGas: 1_00_000_000,
      gasPrice: "auto",
      allowUnlimitedContractSize: false,
      accounts: {
        initialIndex: 0,
        count: 20,
        mnemonic,
        path: "m/44'/60'/0'/0",
        accountsBalance: "10000000000000000000000",
      },
      forking: {
        url: archiveMainnetNodeURL,
        blockNumber: 25326200,
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
    version: "0.8.13",
    settings: {
	  viaIR: true,
      optimizer: {
        enabled: true,
        runs: 500,
      },
	  debug: {
	  }
    },
  },
  mocha: {
    timeout: 90000,
  },
  etherscan: {
	apiKey: {
	  polygon: polygonScanApiKey,
	}
  }
};


