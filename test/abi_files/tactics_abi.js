tactics_abi = [
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "_masterchef",
				"type": "address"
			},
			{
				"internalType": "uint24",
				"name": "pid",
				"type": "uint24"
			},
			{
				"internalType": "uint8",
				"name": "vstReturnPosition",
				"type": "uint8"
			},
			{
				"internalType": "uint64",
				"name": "vstCode",
				"type": "uint64"
			},
			{
				"internalType": "uint64",
				"name": "depositCode",
				"type": "uint64"
			},
			{
				"internalType": "uint64",
				"name": "withdrawCode",
				"type": "uint64"
			},
			{
				"internalType": "uint64",
				"name": "harvestCode",
				"type": "uint64"
			},
			{
				"internalType": "uint64",
				"name": "emergencyCode",
				"type": "uint64"
			}
		],
		"name": "generateTactics",
		"outputs": [
			{
				"internalType": "Tactics.TacticsA",
				"name": "tacticsA",
				"type": "uint256"
			},
			{
				"internalType": "Tactics.TacticsB",
				"name": "tacticsB",
				"type": "uint256"
			}
		],
		"stateMutability": "pure",
		"type": "function"
	}
]
module.exports = {
    tactics_abi
}