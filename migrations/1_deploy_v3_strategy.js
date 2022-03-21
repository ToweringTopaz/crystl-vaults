const { accounts } = require('../configs/addresses.js');
const { ethers } = require('hardhat');
const { dfynVaults } = require('../configs/dfynVaults.js'); //<-- normal and maximizer vault(s)


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


