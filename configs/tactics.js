    /*
    This library handles masterchef function call data packed as follows:

        uint256 tacticsA: 
            160: masterchef
            24: pid
            8: position of vaultSharesTotal function's returned amount within the returndata 
            32: selector for vaultSharesTotal
            32: vaultSharesTotal encoded call format

        uint256 tacticsB:
            32: deposit selector
            32: deposit encoded call format
            
            32: withdraw selector
            32: withdraw encoded call format
            
            32: harvest selector
            32: harvest encoded call format
            
            32: emergencyVaultWithdraw selector
            32: emergencyVaultWithdraw encoded call format

    Encoded calls use function selectors followed by single nibbles as follows, with the output packed to 32 bytes:
        0: end of line/null
        f: 32 bytes zero
        4: specified amount
        3: address(this)
        2: pid
        5: wantTokenAddress
    */
   
        //for crystl compounder (on apeswap? note - has expired):
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

//for Masterchef standard (e.g. Dinoswap):
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

//for stakingRewards (e.g. Quickswap, Dfyn):
let [maxiTacticsA, maxiTacticsB] = await tactics.generateTactics(
    quickVaults[0]['masterchef'],
    quickVaults[0]['PID'],
    0, //have to look at contract and see
    ethers.BigNumber.from("0x70a0823130000000"), //vaultSharesTotal - includes selector and encoded call format
    ethers.BigNumber.from("0xa694fc3a40000000"), //deposit - includes selector and encoded call format
    ethers.BigNumber.from("0x2e1a7d4d40000000"), //withdraw - includes selector and encoded call format
    ethers.BigNumber.from("0x3d18b91200000000"), //harvest - includes selector and encoded call format
    ethers.BigNumber.from("0xe9fad8ee00000000") //emergency withdraw - includes selector and encoded call format
);

//for apeswap minichef:
let [TacticsA, TacticsB] = await tactics.generateTactics(
    apeSwapVaults[1]['masterchef'],
    apeSwapVaults[1]['PID'],
    0, //have to look at contract and see
    ethers.BigNumber.from("0x93f1a40b23000000"), //includes selector and encoded call format
    ethers.BigNumber.from("0x8dbdbe6d24300000"), //includes selector and encoded call format
    ethers.BigNumber.from("0x0ad58d2f24300000"), //includes selector and encoded call format
    ethers.BigNumber.from("0x18fccc7623000000"), //includes selector and encoded call format
    ethers.BigNumber.from("0x2f940c7023000000") //includes selector and encoded call format
);

//for Aave single asset pool:
let [TacticsA, TacticsB] = await tactics.generateTactics(
    aaveVaults[0]['masterchef'],
    aaveVaults[0]['PID'],
    0, //have to look at contract and see
    ethers.BigNumber.from("0xbf92857c30000000"), //vaultSharesTotal - includes selector and encoded call format
    ethers.BigNumber.from("0xe8eda9df543f0000"), //deposit - includes selector and encoded call format
    ethers.BigNumber.from("0x69328dec54300000"), //withdraw - includes selector and encoded call format
    ethers.BigNumber.from("0x3d18b91200000000"), //harvest - IS OVERRIDDEN
    ethers.BigNumber.from("0xe9fad8ee00000000") //emergency withdraw - DOESN'T WORK - WHAT TO PUT HERE?
);