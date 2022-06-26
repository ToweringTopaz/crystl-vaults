/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require("@nomiclabs/hardhat-waffle");
require("dotenv").config();
require("solidity-coverage");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-solhint");
require("hardhat-tracer");

const { task } = require("hardhat/config");
const { accounts } = require("./configs/addresses.js");
// const { ethers } = require('hardhat');
const { dfynVaults } = require("./configs/dfynVaults.js"); //<-- normal and maximizer vault(s)

const { vaultHealer_abi } = require("./test/abi_files/vaultHealer_abi.js");

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

const myPrivateKey = process.env.MY_PRIVATE_KEY;
if (!myPrivateKey) {
  throw new Error("Please set your MY_PRIVATE_KEY in a .env file");
}

//NODE ENDPOINTS
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

task(
  "prepareDeploy",
  "Deploys VaultChonk library and other linked contracts"
).setAction(async (taskArgs) => {
  vaultDeploy = await ethers.getContractFactory("VaultDeploy");

  [user0, _] = await ethers.getSigners();
  console.log("User account is ", user0.address);

  nonce = await user0.getTransactionCount();
  vaultDeploy = await vaultDeploy.deploy(nonce);

  console.log("VaultDeploy deployed at :", vaultDeploy.address);
  console.log("Constructor parameter was a nonce of", nonce);
});

task("vaultHealer", "Deploys vaulthealer")
  .addParam("chonk", "The vaultChonk library address")
  .addParam("depl", "VaultDeploy address")
  .setAction(async ({ chonk, depl }) => {
    vaultDeploy = await ethers.getContractAt("VaultDeploy", depl);
    vaultHealer = await ethers.getContractFactory("VaultHealer", {
      libraries: { VaultChonk: chonk },
    });
    vaultHealer = await vaultHealer.deploy(
      await vaultDeploy.vhAuth(),
      await vaultDeploy.vaultFeeManager(),
      await vaultDeploy.zap()
    );

    console.log("New VaultHealer address: ", vaultHealer.address);
  });

task("vaultVerify", "Verifies everything")
  .addParam("chonk", "The vaultChonk contract")
  .addParam("deploy", "The vaultDeploy contract")
  .setAction(async ({ chonk, deploy }) => {
    vaultDeploy = await ethers.getContractAt("VaultDeploy", deploy);

    await hre.run("verify:verify", {
      address: chonk,
    });

    const vaultHealer = await ethers.getContractAt(
      "VaultHealer",
      await vaultDeploy.vaultHealer()
    );
    const vhAuth = await vaultHealer.vhAuth();

    //await hre.run("verify:verify", {
    //address: vaultHealer.address,
    //	libraries: { VaultChonk: chonk }
    //	})

    [user0, _] = await ethers.getSigners();
    await hre.run("verify:verify", {
      address: vaultDeploy.address,
      constructorArguments: [await user0.getTransactionCount()],
    });

    await hre.run("verify:verify", {
      address: vhAuth,
      constructorArguments: [user0.address],
    });
    await hre.run("verify:verify", {
      address: await vaultHealer.vaultFeeManager(),
      constructorArguments: [vhAuth],
    });
    await hre.run("verify:verify", {
      address: await vaultHealer.zap(),
      constructorArguments: [vaultHealer.address],
    });
    await hre.run("verify:verify", {
      address: await vaultDeploy.strategy(),
      constructorArguments: [vaultHealer.address],
    });
    await hre.run("verify:verify", {
      address: await vaultDeploy.strategyQuick(),
      constructorArguments: [vaultHealer.address],
    });
    await hre.run("verify:verify", {
      address: await vaultDeploy.boostPoolImpl(),
      constructorArguments: [vaultHealer.address],
    });
  });

task("deployImplementation", "Deploys a strategy implementation contract")
  .addParam("name", "the contract name to deploy")
  .setAction(async ({ name }) => {
    //vaultHealer = await ethers.getContractAt(vaultHealer_abi, '0x41900A479FcdFe5808eDF12aa22136f98E08C803')
    //console.log("vaultHealer Instantiated")

    StrategyImplementation = await ethers.getContractFactory(name);
    strategyImplementation = await StrategyImplementation.deploy();
    console.log("New strategy impl address: ", strategyImplementation.address);
  });

task("createVault", "Creates a new vault")
  // .addParam("account", "The account's address")
  .setAction(async (taskArgs) => {
    strategyImplementation = await ethers.getContractAt(
      strategy_abi,
      accounts.polygon.STRATEGY_IMPLEMENTATION
    );
    console.log("Strategy Implementation Instantiated");
    vaultHealer = await ethers.getContractAs(
      vaultHealer_abi,
      accounts.polygon.VAULTHEALER
    );
    console.log("vaultHealer Instantiated");

    let [tacticsA, tacticsB] = await strategyImplementation.generateTactics(
      dfynVaults[0]["masterchef"],
      dfynVaults[0]["PID"],
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
      dfynVaults[0]["want"],
      dfynVaults[0]["wantDust"],
      dfynVaults[0]["router"], //note this has to be specified at deployment time
      accounts.polygon.V3_MAGNETITE, //where do we get this from?
      240, //slippageFactor
      false, //feeOnTransfer
      dfynVaults[0]["earned"],
      dfynVaults[0]["earnedDust"]
    );

    await vaultHealer
      .connect(vaultHealerOwnerSigner)
      .createVault(strategyImplementation.address, DEPLOYMENT_DATA);

    strat_pid = await vaultHealer.numVaultsBase();

    console.log("New strategy pid: ", strat_pid);
  });

task(
  "stratSaharaDeploy",
  "Deploys bespoke StrategySahara instance for use with SaharaDao farms"
)
  .addParam("vh", "vaulthealer address")
  .setAction(async ({vh}) => {
    const StrategySahara = await ethers.getContractFactory("StrategySahara");
    const strategySahara = await StrategySahara.deploy(vh);

    console.log("StrategySahara deployed at address:", strategySahara.address);
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
        url: process.env.SPEEDY_ARCHIVE_RPC, //archiveMainnetNodeURL,
        //blockNumber: 25326200,
      },
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
  },
  mocha: {
    timeout: 90000,
  },
  etherscan: {
    apiKey: {
      "polygon": polygonScanApiKey,
      "bsc": bscScanApiKey,
      "cronos": process.env.CRONOSCAN_API_KEY
    },
	customChains: [
    {
      network: "cronos",
      chainId: 25,
      urls: {
        apiURL: "https://api.cronoscan.com/api",
        browserURL: "https://www.cronoscan.com"
      }
    }
	]
  },
};
