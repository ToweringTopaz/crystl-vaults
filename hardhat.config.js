/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("@nomiclabs/hardhat-waffle");
require("dotenv").config();
require("solidity-coverage");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-solhint");
require("hardhat-tracer");

require("./tasks/Deploys/core");
require("./tasks/Deploys/periphery");
require("./tasks/Deploys/strategy");
require("./tasks/Verification/verify");

// const { ethers } = require('hardhat');

const chainIds = {
  hardhat: 31337,
};
/////////////////////////////////////////////////////////////////
/// Ensure that we have all the environment variables we need.///
/////////////////////////////////////////////////////////////////
const mnemonic = process.env.MNEMONIC;
if (!mnemonic) {
  throw new Error("Please set your MNEMONIC in a .env file");
}

const myPrivateKey = process.env.MY_PRIVATE_KEY;
if (!myPrivateKey) {
  throw new Error("Please set your MY_PRIVATE_KEY in a .env file");
}
//////////////////////////////////////////////////////
////////////////////NODE ENDPOINTS////////////////////
//////////////////////////////////////////////////////
const archiveMainnetNodeURL = process.env.SPEEDY_ARCHIVE_RPC;
if (!archiveMainnetNodeURL) {
  throw new Error(
    "Please set your  SPEEDY_ARCHIVE_RPC in a .env file, ensuring it's for the relevant blockchain"
  );
}
const polygonMainnetNodeURL = process.env.POLYGON_PRIVATE_RPC;
if (!polygonMainnetNodeURL) {
  throw new Error("Please set your POLYGON_PRIVATE_RPC in a .env file");
}
const bscMainnetNodeURL = process.env.BNB_PRIVATE_RPC;
if (!bscMainnetNodeURL) {
  throw new Error("Please set your BNB_PRIVATE_RPC in a .env file");
}
const cronosMainnetNodeURL = process.env.CRONOS_PRIVATE_RPC;
if (!cronosMainnetNodeURL) {
  throw new Error("Please set your CRONOS_PRIVATE_RPC in a .env file");
}
const bttcMainnetNodeURL = process.env.BTTC_PRIVATE_RPC;
if (!bttcMainnetNodeURL) {
  throw new Error("Please set your BTTC_PRIVATE_RPC in a .env file");
}
const iotexMainnetNodeURL = process.env.IOTEX_PRIVATE_RPC;
if (!iotexMainnetNodeURL) {
  throw new Error("Please set your IOTEX_PRIVATE_RPC in a .env file");
}
const moonbeamMainnetNodeUrl = process.env.MOONBEAM_PRIVATE_RPC;
if (!moonbeamMainnetNodeUrl) {
  throw new Error("Please set your MOONBEAM_PRIVATE_RPC in a .env file");
}
const optimismMainnetNodeUrl = process.env.OPTIMISM_PRIVATE_RPC;
if (!optimismMainnetNodeUrl) {
  throw new Error("Please set your OPTIMISM_PRIVATE_RPC in a .env file");
}
/////////////////////////////////////////////////////////
////////////////////EtherScan API Keys///////////////////
/////////////////////////////////////////////////////////
const polygonScanApiKey = process.env.POLYGONSCAN_API_KEY;
if (!polygonScanApiKey) {
  throw new Error("Please set your POLYGONSCAN_API_KEY in a .env file");
}
const bscScanApiKey = process.env.BSCSCAN_API_KEY;
if (!bscScanApiKey) {
  throw new Error("Please set your BSCSCAN_API_KEY in a .env file");
}
const cronoScanApiKey = process.env.CRONOSCAN_API_KEY;
if (!cronoScanApiKey) {
  throw new Error("Please set your CRONOSCAN_API_KEY in a .env file");
}

// The following etherscan versions may require some extra configuration within the guts of the dist file of @nomiclabs/hardhat-etherscan :)
 //NODE ENDPOINTS 
 const archiveMainnetNodeURL = process.env.SPEEDY_ARCHIVE_RPC;
 if (!archiveMainnetNodeURL) {
   throw new Error("Please set your  SPEEDY_ARCHIVE_RPC in a .env file, ensuring it's for the relevant blockchain");
 }
 const polygonMainnetNodeURL = process.env.POLYGON_PRIVATE_RPC;
 if (!polygonMainnetNodeURL) {
   throw new Error("Please set your POLYGON_PRIVATE_RPC in a .env file");
 }
 const bscMainnetNodeURL = process.env.BNB_PRIVATE_RPC;
 if (!bscMainnetNodeURL) {
   throw new Error("Please set your BNB_PRIVATE_RPC in a .env file")
 }
 const cronosMainnetNodeURL = process.env.CRONOS_ARCHIVE_RPC;
 if (!cronosMainnetNodeURL) {
   throw new Error("Please set your CRONOS_ARCHIVE_RPC in a .env file")
 }
 //API Keys
 const polygonScanApiKey = process.env.POLYGONSCAN_API_KEY;
 if (!polygonScanApiKey) {
   throw new Error("Please set your POLYGONSCAN_API_KEY in a .env file");
 }
 const bscScanApiKey = process.env.BSCSCAN_API_KEY;
 if (!bscScanApiKey) {
   throw new Error("Please set your BSCSCAN_API_KEY in a .env file");
 }
 const cronoScanApiKey = process.env.CRONOSCAN_API_KEY;
 if (!cronoScanApiKey) {
   throw new Error("Please set your CRONOSCAN_API_KEY in a .env file");
 }


task("libDeploy", "Deploys a library")
	.addParam("lib", "The library's name")
    .setAction(async (taskArgs) => {
	
	vaultChonk = await ethers.getContractFactory(name);
	vaultChonk = await vaultChonk.deploy();	
	
	console.log(name, "deployed at: ", vaultChonk.address);
	
});


task("prepareDeploy", "Deploys VaultChonk library and other linked contracts")
    .setAction(async (taskArgs) => {
	
	vaultDeploy = await ethers.getContractFactory("VaultDeploy");
	
	[user0, _] = await ethers.getSigners();
	console.log("User account is ", user0.address);
	
	nonce = await user0.getTransactionCount()
	vaultDeploy = await vaultDeploy.deploy(nonce);
	
	console.log("VaultDeploy deployed at :", vaultDeploy.address);
	console.log("Constructor parameter was a nonce of", nonce);
});

task("vaultHealer", "Deploys vaulthealer")
  .addParam("chonk", "The vaultChonk library address")
  .addParam("depl", "VaultDeploy address")
  .setAction(async ({ chonk, depl }) => {

	vaultDeploy = await ethers.getContractAt("VaultDeploy", depl);
    vaultHealer = await ethers.getContractFactory("VaultHealer", {libraries: { VaultChonk: chonk }});
    vaultHealer = await vaultHealer.deploy(await vaultDeploy.vhAuth(), await vaultDeploy.vaultFeeManager(), await vaultDeploy.zap());
    
    console.log("New VaultHealer address: ", vaultHealer.address);
	
  });

task("vaultVerify", "Verifies everything")
  .addParam("chonk", "The vaultChonk contract")
  .addParam("deploy", "The vaultDeploy contract")
  .setAction(async ({ chonk, deploy }) => {
	  
    vaultDeploy = await ethers.getContractAt("VaultDeploy", deploy);

	await hre.run("verify:verify", {
		address: chonk
	})	
	
	const vaultHealer = await ethers.getContractAt("VaultHealer", await vaultDeploy.vaultHealer());
	const vhAuth = await vaultHealer.vhAuth();
	
	//await hre.run("verify:verify", {
		//address: vaultHealer.address,
	//	libraries: { VaultChonk: chonk }
//	})
	
	[user0, _] = await ethers.getSigners();
	await hre.run("verify:verify", {
		address: vaultDeploy.address,
		constructorArguments: [await user0.getTransactionCount()]
	})

	await hre.run("verify:verify", {
		address: vhAuth,
		constructorArguments: [user0.address],
	})
    await hre.run("verify:verify", {
		address: await vaultHealer.vaultFeeManager(),
		constructorArguments: [vhAuth],
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
  .setAction(async (name) => {
    //vaultHealer = await ethers.getContractAt(vaultHealer_abi, '0x41900A479FcdFe5808eDF12aa22136f98E08C803')
    //console.log("vaultHealer Instantiated")
	
    StrategyImplementation = await ethers.getContractFactory("StrategySahara");
    strategyImplementation = await StrategyImplementation.deploy('0xBA6f3b9bf74FbFa59d55E52fa722E6a5737070D0');
    
    console.log("New strategy impl address: ", strategyImplementation.address);
  });

const bttcScanApiKey = process.env.BTTCSCAN_API_KEY;
if (!bttcScanApiKey) {
  throw new Error("Please set your BTTCSCAN_API_KEY in a .env file");
}

// Coming soon, IOTEX Scan is rudamentary vers of Etherscan, does not make use of api keys, but did the legwork anyway for when they do!

// const iotexScanApiKey = process.env.IOTEX_SCAN_API_KEY;
// if (!bttcScanApiKey) {
//   throw new Error("Please set your IOTEX in a .env file")
//}
const moonbeamScanApiKey = process.env.MOONBEAMSCAN_API_KEY;
if (!moonbeamScanApiKey) {
  throw new Error("Please set your MOONBEAMSCAN_API_KEY in a .env file");
}
const optimisticEtherscanApiKey = process.env.OPTIMISTIC_ETHERSCAN_API_KEY;
if (!optimisticEtherscanApiKey) {
  throw new Error(
    "Please set your OPTIMISTIC_ETHERSCAN_API_KEY in a .env file"
  );
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
      //forking: {
        //url: process.env.SPEEDY_ARCHIVE_RPC//archiveMainnetNodeURL,
        //blockNumber: 25326200,
      //},
      chainId: chainIds.hardhat,
      hardfork: "london",
    },

    polygon: {
      url: polygonMainnetNodeURL,
      accounts: [`0x${myPrivateKey}`],
    },
    bsc: {
      url: bscMainnetNodeURL,
      accounts: [`0x${myPrivateKey}`],
    },
    cronos: {
      url: cronosMainnetNodeURL,
      accounts: [`0x${myPrivateKey}`],
    },
    bttc: {
      url: bttcMainnetNodeURL,
      accounts: [`0x${myPrivateKey}`],
    },
    iotex: {
      url: iotexMainnetNodeURL,
      accounts: [`0x${myPrivateKey}`],
    },
    moonbeam: {
      url: moonbeamMainnetNodeUrl,
      accounts: [`0x${myPrivateKey}`],
    },
    optimism: {
      url: optimismMainnetNodeUrl,
      accounts: [`0x${myPrivateKey}`],
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.15",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 255,
            details: {
              peephole: true,
              inliner: true,
              jumpdestRemover: true,
              orderLiterals: true,
              deduplicate: true,
              cse: true,
              constantOptimizer: true,
              yul: true,
            },
          },
        },
      },
    ],
     polygon: {
       url: polygonMainnetNodeURL,
       accounts: [`0x${myPrivateKey}`],
     },
     bsc: {
       url: bscMainnetNodeURL,
       accounts: [`0x${myPrivateKey}`], 
     },
     cronos: {
       url: cronosMainnetNodeURL,
       accounts: [`0x${myPrivateKey}`],
     }
	 optimism: {
       url: optimismMainnetNodeURL,
       accounts: [`0x${myPrivateKey}`],
     }
  },
  solidity: {
	compilers: [{
		version: "0.8.15",
		settings: {
		  viaIR: true,
		  optimizer: {
			enabled: true,
			runs: 255,
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
  },
  mocha: {
    timeout: 90000,
  },
  etherscan: {
    apiKey: {
      polygon: polygonScanApiKey,
      bsc: bscScanApiKey,
      cronos: cronoScanApiKey,
      bttc: bttcScanApiKey,
      iotex: "",
      moonbeam: moonbeamScanApiKey,
      optimism: optimisticEtherscanApiKey,
    },
    customChains: [
      {
        network: "cronos",
        chainId: 25,
        urls: {
          apiURL: "https://api.cronoscan.com/api",
          browserURL: "https://www.cronoscan.com",
        },
      },
    ],
  },
};
