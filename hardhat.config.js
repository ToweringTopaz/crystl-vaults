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

task("deployChonk", "Deploys VaultChonk library")
    .setAction(async (taskArgs) => {
	
	vaultChonk = await ethers.getContractFactory("VaultChonk");
	vaultChonk = await vaultChonk.deploy();	
	
	console.log("VaultChonk deployed at: ", vaultChonk.address);
});

task("vaultHealer", "Deploys everything")
  .addParam("chonk", "The vaultChonk library address")
  .setAction(async ({ chonk }) => {

    vaultHealer = await ethers.getContractFactory("VaultHealer", {libraries: { VaultChonk: chonk }});
    vaultHealer = await vaultDeploy.deploy();
    
    console.log("New VaultDeploy address: ", vaultDeploy.address);
	
  });

task("testVaultDeploy", "Deploys everything and initializes it as a test VaultHealer")
  .addParam("chonk", "The vaultChonk library address")
  .setAction(async ({ chonk }) => {

    vaultDeploy = await ethers.getContractFactory("TestVaultDeploy", {libraries: { VaultChonk: chonk }});
    vaultDeploy = await vaultDeploy.deploy();
    
    console.log("New deploy address: ", vaultDeploy.address);
	
  });

task("vaultVerify", "Verifies everything")
  .addParam("chonk", "The vaultChonk contract")
  .addParam("deploy", "The vaultDeploy contract")
  .setAction(async ({ chonk, deploy }) => {
	  
    vaultDeploy = await ethers.getContractAt("VaultDeploy", deploy);

	await hre.run("verify:verify", {
		address: chonk
	})	
	
//	await hre.run("verify:verify", {
//		address: vaultDeploy.address,
//		libraries: { VaultChonk: chonk }
//	})
	const vaultHealer = await ethers.getContractAt("VaultHealer", await vaultDeploy.vaultHealer());
	const vhAuth = await ethers.getContractAt("VaultHealerAuth", await vaultHealer.vhAuth());
	
//	await hre.run("verify:verify", {
//		address: vaultHealer.address
//	})
//	await hre.run("verify:verify", {
//		address: vhAuth.address,
//		constructorArguments: [vaultDeploy.address],
//	})
    await hre.run("verify:verify", {
		address: await vaultHealer.vaultFeeManager(),
		constructorArguments: [vhAuth.address],
	})	
	await hre.run("verify:verify", {
		address: await vaultHealer.zap(),
		constructorArguments: [ vaultHealer.address ],
	})	
	await hre.run("verify:verify", {
		address: await vaultDeploy.strategy(),
		constructorArguments: [ vaultHealer.address ],
	})
	await hre.run("verify:verify", {
		address: await vaultDeploy.strategyQuick(),
		constructorArguments: [ vaultHealer.address ],
	})	
	await hre.run("verify:verify", {
		address: await vaultDeploy.boostPoolImpl(),
		constructorArguments: [ vaultHealer.address ],
	})		
	
  });


task("deployImplementation", "Deploys a strategy implementation contract")
  .addParam("name", "The contract's name")
  .setAction(async (taskArgs) => {
    vaultHealer = await ethers.getContractAs(vaultHealer_abi, accounts.polygon.VAULTHEALER)
    console.log("vaultHealer Instantiated")
	
    StrategyImplementation = await ethers.getContractFactory("Strategy");
    strategyImplementation = await StrategyImplementation.deploy();
    
    console.log("New strategy impl address: ", strategyImplementation.address);
  });

task("createVault", "Creates a new vault")
  // .addParam("account", "The account's address")
  .setAction(async (taskArgs) => {
    strategyImplementation =  await ethers.getContractAt(strategy_abi, accounts.polygon.STRATEGY_IMPLEMENTATION);
    console.log("Strategy Implementation Instantiated")
    vaultHealer = await ethers.getContractAs(vaultHealer_abi, accounts.polygon.VAULTHEALER)
    console.log("vaultHealer Instantiated")

    let [tacticsA, tacticsB] = await strategyImplementation.generateTactics(
      dfynVaults[0]['masterchef'],
      dfynVaults[0]['PID'],
      0, //position of return value in vaultSharesTotal returnData array - have to look at contract and see
      ethers.BigNumber.from("0x70a0823130000000"), //vaultSharesTotal - includes selector and encoded call format
      ethers.BigNumber.from("0xa694fc3a40000000"), //deposit - includes selector and encoded call format
      ethers.BigNumber.from("0x2e1a7d4d40000000"), //withdraw - includes selector and encoded call format
      ethers.BigNumber.from("0x3d18b91200000000"), //harvest - includes selector and encoded call format
      ethers.BigNumber.from("0xe9fad8ee00000000") //emergency withdraw - includes selector and encoded call format
    );
    
    DEPLOYMENT_DATA = await strategyImplementation.generateConfig(
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
	compilers: [{
		version: "0.8.13",
		settings: {
		  viaIR: true,
		  optimizer: {
			enabled: true,
			runs: 1000000,
			details: {
				peephole: true,
				inliner: true,
				jumpdestRemover: true,
				orderLiterals: true,
				deduplicate: true,
				cse: true,
				constantOptimizer: true,
				yul: true
			}
		  },
		},
	}],
	overrides: {
		"contracts/VaultHealer.sol": {
			version: "0.8.13",
			settings: {
			  viaIR: true,
			  optimizer: {
				enabled: true,
				runs: 1,
				details: {
					peephole: true,
					inliner: true,
					jumpdestRemover: true,
					orderLiterals: true,
					deduplicate: true,
					cse: true,
					constantOptimizer: true,
					yul: true
				}
			  },
			},
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


