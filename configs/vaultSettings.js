const { accounts, tokens, masterChefs, lps, routers } = require('./addresses.js');
const { FEE_ADDRESS, BURN_ADDRESS } = accounts.polygon;

const vaultSettings = {
	standard: [
		routers.polygon.APESWAP_ROUTER, //aperouter
		FEE_ADDRESS, // withdrawFee
		FEE_ADDRESS, // rewardFee		
		BURN_ADDRESS, //buybackFee
		50, //uint16 controllerFee;
        50, //uint16 rewardRate;
        400, //uint16 buybackRate;
        9990, //uint256 withdrawFeeFactor;
        9500, //uint256 slippageFactor;
        1, //uint256 tolerance;
        false, //bool feeOnTransfer;
        100000, //uint256 dust; //minimum raw token value considered to be worth swapping or depositing
        10 //uint256 minBlocksBetweenSwaps;
	],
	reflect: [
		routers.polygon.APESWAP_ROUTER, //aperouter
		FEE_ADDRESS, // withdrawFee
		FEE_ADDRESS, // rewardFee
		BURN_ADDRESS, //buybackFee
		50, //uint16 controllerFee;
        50, //uint16 rewardRate;
        400, //uint16 buybackRate;
        9990, //uint256 withdrawFeeFactor;
        9000, //uint256 slippageFactor;
        1, //uint256 tolerance;
        true, //bool feeOnTransfer;
        1000000000000, //uint256 dust; //minimum raw token value considered to be worth swapping or depositing
        10 //uint256 minBlocksBetweenSwaps;
	],
	doubleReflect: [
		routers.polygon.APESWAP_ROUTER, //aperouter
		FEE_ADDRESS, // rewardFee
		FEE_ADDRESS, // withdrawFee
		BURN_ADDRESS, //buybackFee
		50, //uint16 controllerFee;
        50, //uint16 rewardRate;
        400, //uint16 buybackRate;
        9990, //uint256 withdrawFeeFactor;
        8000, //uint256 slippageFactor;
        1, //uint256 tolerance;
        true, //bool feeOnTransfer;
        1000000000000, //uint256 dust; //minimum raw token value considered to be worth swapping or depositing
        10 //uint256 minBlocksBetweenSwaps;
	],
}
module.exports = {
	vaultSettings
}