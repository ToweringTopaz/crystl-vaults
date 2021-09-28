const vaultSettings = {
	standard: [
		50, //uint16 controllerFee;
        50, //uint16 rewardRate;
        400, //uint16 buybackRate;
        9990, //uint256 withdrawFeeFactor;
        9500, //uint256 slippageFactor;
        1, //uint256 tolerance;
        false, //bool feeOnTransfer;
        1000000000000, //uint256 dust; //minimum raw token value considered to be worth swapping or depositing
        10 //uint256 minBlocksBetweenSwaps;
	],
	reflect: [
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