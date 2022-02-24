//for crystl compounder:
let [crystlTacticsA, crystlTacticsB] = await tactics.generateTactics(
    crystlVault[0]['masterchef'],
    crystlVault[0]['PID'],
    0, //have to look at contract and see
    ethers.BigNumber.from("0x93f1a40b23000000"), //includes selector and encoded call format
    ethers.BigNumber.from("0xe2bbb15824000000"), //includes selector and encoded call format
    ethers.BigNumber.from("0x441a3e7024000000"), //includes selector and encoded call format
    ethers.BigNumber.from("0xe2bbb1582f000000"), //includes selector and encoded call format
    ethers.BigNumber.from("0x5312ea8e20000000") //includes selector and encoded call format
);

//for Masterchef standard:
let [tacticsA, tacticsB] = await tactics.generateTactics(
    dinoswapVaults[0]['masterchef'],
    dinoswapVaults[0]['PID'],
    0, //position of return value in vaultSharesTotal returnData array - have to look at contract and see
    ethers.BigNumber.from("0x93f1a40b23000000"), //vaultSharesTotal - includes selector and encoded call format
    ethers.BigNumber.from("0xe2bbb15824000000"), //deposit - includes selector and encoded call format
    ethers.BigNumber.from("0x441a3e7024000000"), //withdraw - includes selector and encoded call format
    ethers.BigNumber.from("0x441a3e702f000000"), //harvest - includes selector and encoded call format
    ethers.BigNumber.from("0x5312ea8e20000000") //includes selector and encoded call format
);

let [maxiTacticsA, maxiTacticsB] = await tactics.generateTactics(
    dinoswapVaults[0]['masterchef'],
    dinoswapVaults[0]['PID'],
    0, //have to look at contract and see
    ethers.BigNumber.from("0x93f1a40b23000000"), //vaultSharesTotal - includes selector and encoded call format
    ethers.BigNumber.from("0xe2bbb15824000000"), //deposit - includes selector and encoded call format
    ethers.BigNumber.from("0x441a3e7024000000"), //withdraw - includes selector and encoded call format
    ethers.BigNumber.from("0x441a3e702f000000"), //harvest - includes selector and encoded call format
    ethers.BigNumber.from("0x5312ea8e20000000") //includes selector and encoded call format
);

//for apeswap minichef:
let [maxiTacticsA, maxiTacticsB] = await tactics.generateTactics(
    apeSwapVaults[1]['masterchef'],
    apeSwapVaults[1]['PID'],
    0, //have to look at contract and see
    ethers.BigNumber.from("0x93f1a40b23000000"), //includes selector and encoded call format
    ethers.BigNumber.from("0x8dbdbe6d24300000"), //deposit - includes selector and encoded call format
    ethers.BigNumber.from("0x0ad58d2f24300000"), //withdraw - includes selector and encoded call format
    ethers.BigNumber.from("0x18fccc7623000000"), //harvest - includes selector and encoded call format
    ethers.BigNumber.from("0x2f940c7023000000") //emergencyWithdraw - includes selector and encoded call format
);

//for stakingRewards:
let [tacticsA, tacticsB] = await tactics.generateTactics(
    dinoswapVaults[0]['masterchef'],
    dinoswapVaults[0]['PID'],
    0, //position of return value in vaultSharesTotal returnData array - have to look at contract and see
    ethers.BigNumber.from("0x70a0823130000000"), //vaultSharesTotal - includes selector and encoded call format
    ethers.BigNumber.from("0x694fc3a940000000"), //deposit - includes selector and encoded call format
    ethers.BigNumber.from("0x2e1a7d4d40000000"), //withdraw - includes selector and encoded call format
    ethers.BigNumber.from("0x3d18b91200000000"), //harvest - includes selector and encoded call format
    ethers.BigNumber.from("0xe9fad8ee20000000") //emergencyWithdraw - includes selector and encoded call format
);