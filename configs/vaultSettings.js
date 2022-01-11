const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;

const vaultSettings = {
	standard: [
		routers.polygon.APESWAP_ROUTER, //aperouter
        9500, //uint256 slippageFactor;
        1, //uint256 tolerance;
		10, //uint256 minBlocksBetweenSwaps;
        false, //bool feeOnTransfer;
		ZERO_ADDRESS, //Magnetite == vaultHealer; this value is initialized automatically later
		1000000000000 //uint256 dust; //minimum raw token value considered to be worth swapping or depositing
	],
	reflect: [
		routers.polygon.APESWAP_ROUTER, //aperouter
        9000, //uint256 slippageFactor;
        1, //uint256 tolerance;
		10, //uint256 minBlocksBetweenSwaps;
        true, //bool feeOnTransfer;
		ZERO_ADDRESS, //Magnetite == vaultHealer; this value is initialized automatically later
		1000000000000 //uint256 dust; //minimum raw token value considered to be worth swapping or depositing
	],
	doubleReflect: [
		routers.polygon.APESWAP_ROUTER, //aperouter
        9000, //uint256 slippageFactor;
        1, //uint256 tolerance;
		10, //uint256 minBlocksBetweenSwaps;
        true, //bool feeOnTransfer;
		ZERO_ADDRESS, //Magnetite == vaultHealer; this value is initialized automatically later
		1000000000000 //uint256 dust; //minimum raw token value considered to be worth swapping or depositing
	]
}
// const feeConfig = {
// 	standard: [
// 	// withdraw fee: token is not set here; standard fee address; 10 now means 0.1% consistent with other fees
// 		[ ZERO_ADDRESS, FEE_ADDRESS, 10 ],
// 		[ WMATIC, FEE_ADDRESS, 50 ], //earn fee: wmatic is paid; receiver is ignored; 0.5% rate
// 		[ DAI, FEE_ADDRESS, 50 ], //reward fee: paid in DAI; standard fee address; 0.5% rate
// 		[ CRYSTL, BURN_ADDRESS, 400 ] //burn fee: crystl to burn address; 4% rate
// }
module.exports = {
	vaultSettings
}

// FEE_ADDRESS, // withdrawFee
// 		FEE_ADDRESS, // rewardFee		
// 		BURN_ADDRESS, //buybackFee
// 		50, //uint16 controllerFee;
//         50, //uint16 rewardRate;
//         400, //uint16 buybackRate;
//         9990, //uint256 withdrawFeeFactor;