strategyConfig_abi = [
	{
		"inputs": [
			{
				"internalType": "Tactics.TacticsA",
				"name": "_tacticsA",
				"type": "uint256"
			},
			{
				"internalType": "Tactics.TacticsB",
				"name": "_tacticsB",
				"type": "uint256"
			},
			{
				"internalType": "address",
				"name": "_wantToken",
				"type": "address"
			},
			{
				"internalType": "uint8",
				"name": "_wantDust",
				"type": "uint8"
			},
			{
				"internalType": "address",
				"name": "_router",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "_magnetite",
				"type": "address"
			},
			{
				"internalType": "uint8",
				"name": "_slippageFactor",
				"type": "uint8"
			},
			{
				"internalType": "bool",
				"name": "_feeOnTransfer",
				"type": "bool"
			},
			{
				"internalType": "address[]",
				"name": "_earned",
				"type": "address[]"
			},
			{
				"internalType": "uint8[]",
				"name": "_earnedDust",
				"type": "uint8[]"
			}
		],
		"name": "generateConfig",
		"outputs": [
			{
				"internalType": "bytes",
				"name": "configData",
				"type": "bytes"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "configData",
				"type": "bytes"
			}
		],
		"name": "test",
		"outputs": [
			{
				"internalType": "Tactics.TacticsA",
				"name": "_tacticsA",
				"type": "uint256"
			},
			{
				"internalType": "Tactics.TacticsB",
				"name": "_tacticsB",
				"type": "uint256"
			},
			{
				"internalType": "contract IERC20",
				"name": "want",
				"type": "IERC20"
			},
			{
				"internalType": "uint256",
				"name": "wantDust",
				"type": "uint256"
			},
			{
				"internalType": "contract IUniRouter",
				"name": "_router",
				"type": "IUniRouter"
			},
			{
				"internalType": "contract IMagnetite",
				"name": "_magnetite",
				"type": "IMagnetite"
			}
		],
		"stateMutability": "pure",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes",
				"name": "configData",
				"type": "bytes"
			}
		],
		"name": "test2",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "_slippageFactor",
				"type": "uint256"
			},
			{
				"internalType": "bool",
				"name": "_feeOnTransfer",
				"type": "bool"
			},
			{
				"internalType": "contract IERC20[]",
				"name": "_earned",
				"type": "IERC20[]"
			},
			{
				"internalType": "uint256[]",
				"name": "_dust",
				"type": "uint256[]"
			}
		],
		"stateMutability": "pure",
		"type": "function"
	}
]
module.exports = {
    strategyConfig_abi
}