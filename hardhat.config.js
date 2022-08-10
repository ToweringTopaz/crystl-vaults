

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 require("dotenv").config();
 require("solidity-coverage");
 require("@nomiclabs/hardhat-etherscan");
 require("@nomiclabs/hardhat-ethers")
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
 const ftmMainnetNodeUrl = process.env.FTM_PRIVATE_RPC;
 if (!ftmMainnetNodeUrl) {
   throw new Error("Please Set your FTM_PRIVATE_RPC in a .env file");
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
 const ftmScanApiKey = process.env.FTMSCAN_API_KEY;
 if(!ftmScanApiKey) {
   throw new Error("Please set your FTMSCAN_API_KEY in a .env file");
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
         url: polygonMainnetNodeURL,
         blockNumber: 25326200,
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
     ftm: {
       url: ftmMainnetNodeUrl,
       accounts: [`0x${myPrivateKey}`]
     }
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
       polygon: polygonScanApiKey,
       bsc: bscScanApiKey,
       cronos: cronoScanApiKey,
       bttc: bttcScanApiKey,
       iotex: "",
       moonbeam: moonbeamScanApiKey,
       optimisticEthereum: optimisticEtherscanApiKey,
       opera: ftmScanApiKey
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
 