const accounts = {
        polygon: {
                ADMIN_ADDRESS: "0xCE34Ccb6481fdc85953fd870343b24816A325351",
                FEE_ADDRESS: "0x5386881b46C37CdD30A748f7771CF95D7B213637",
                NEW_TEST_VAULT_HEALER: '0x619b42b89817dc9FE5e021ACb1A8334DCd70667D',
                STAGING_VAULT_HEALER: '0x94C0BBC3A594d0C7Af0179eD21d0b9b4018e3085',
                PRODUCTION_VAULT_HEALER: '0xD4d696ad5A7779F4D3A0Fc1361adf46eC51C632d'
        }
}
 
const tokens = {
        polygon: {
                CRYSTL: '0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64',
                WMATIC: '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270',
                WETH: '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619',
                DINO: '0xAa9654BECca45B5BDFA5ac646c939C62b527D394',
                USDC: '0x2791bca1f2de4661ed88a30c99a7a9449aa84174',
                USDT: '0xc2132d05d31c914a87c6611c10748aeb04b58e8f',
                DAI: '0x8f3cf7ad23cd3cadbd9735aff958023239c6a063',
                PWINGS: '0x845E76A8691423fbc4ECb8Dd77556Cb61c09eE25',
                WBTC: '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6',
                HAIR: '0x100A947f51fA3F1dcdF97f3aE507A72603cAE63C',
                BANANA: '0x5d47baba0d66083c52009271faf3f50dcc01023c',
                SING: '0xcb898b0efb084df14dd8e018da37b4d0f06ab26d',
                SX: '0x840195888db4d6a99ed9f73fcd3b225bb3cb1a79',
                KAVIAN: '0xc4df0e37e4ad3e5c6d1df12d3ca7feb9d2b67104',
                GPUL: '0x40ed0565ecfb14ebcdfe972624ff2364933a8ce3',
                GBNT: "0x8c9aaca6e712e2193acccbac1a024e09fb226e51",
                TAKO: '0x6D2a71f4edF10ab1E821B9B373363e1E24E5DF6b',
                INKU: '0x1Dd9e9e142f3f84d90aF1a9F2cb617C7e08420a4',
                ROLL: '0xc68e83a305b0fad69e264a1769a0a070f190d2d6',
                QUICK: '0x831753DD7087CaC61aB5644b308642cc1c33Dc13',
                KOM: '0xC004e2318722EA2b15499D6375905d75Ee5390B8',
        }
}
 
 const masterChefs = {
         polygon: {
                BARBER_MASTERCHEF: '0xC6Ae34172bB4fC40c49C3f53badEbcE3Bb8E6430',
                DINOSWAP_MASTERCHEF: '0x1948abc5400aa1d72223882958da3bec643fb4e5',
                JETSWAP_MASTERCHEF: '0x4e22399070aD5aD7f7BEb7d3A7b543e8EcBf1d85',
                KAVIAN_MASTERCHEF: '0x90ab4f52bd975dcb17965666c98fc908fa173d31',
                POLYPULSAR_GAMMA_MASTERCHEF: '0xa375495919205251a05f3b259b4d3cc30a4d3ed5',
                TAKO_MASTERCHEF: '0xB19300246e19929a617C4260189f7B759597B8d8',
                POLYROLL_MASTERCHEF: '0x3C58EA8D37f4fc6882F678f822E383Df39260937',
                QUICK_MASTERCHEF: '0x2f58B48A013BAde935e43f7bCc31f1378Ae68d55',
                APESWAP_MINICHEF: '0x54aff400858Dcac39797a81894D9920f16972D1D',
         }
}

const lps = {
        polygon: {
                HAIR_USDC_APE_LP: '0xb394009787c2d0cb5b45d06e401a39648e21d681', // pid: 8
                MATIC_SING_APE_LP: '0x854d3639f38f65c091664062230091858955ddc2', // barber pid: 10
                MATIC_CRYSTL_APE_LP: '0xB8e54c9Ea1616beEBe11505a419DD8dF1000E02a', // barber pid: 9, tako pid = 5, apeswap pid = 7
                ETH_SX_SUSHI_LP: '0x1bf9805b40a5f69c7d0f9e5d1ab718642203c652', // dino pid: 4
                WBTC_WETH_JET_LP: '0x173e90f2a94af3b075deec7e64df4d70efb4ac3d', // jet pid: 14
                USDC_USDT_JET_LP: '0x20bf018fddba3b352f3d913fe1c81b846fe0f490', // jet pid: 15
                USDC_KAVIAN_QUICK_LP: '0x0a4374b0d63597a5d314ad65fb687892bcaab22e', // kavian pid: 0
                MATIC_GPUL_CAT_LP: '0xc6fcd85ddd4a301c9babffefc07dadddf7b413a4', // gpul farm pid: 0
                MATIC_GBNT_CAT_LP: "0xd883c361d1e8a7e1f77d38e0a6e45d897006b798",
                MATIC_TAKO_APE_LP: '0xd30f018e0DD3c9FD1fF5077a05D86bA82d04c73C', // tako pid = 0
                MATIC_INKU_APE_LP: '0x5bfd0CA929aC41e110B709a5be069Cb7D5D8A15e', // tako pid = 6
                BANANA_ETH_APE_LP: '0x44b82c02F404Ed004201FB23602cC0667B1D011e', // tako pid = 4
                MATIC_ROLL_APE_LP: '0x65c37f48781a555e2ad5542e4306ebab1ae93cd7', // polyroll pid = 8
                QUICK_KOM_QUICK_LP: '0x082b58350a04D8D38b4BCaE003BB1191b9aae565', //quick pid = ?
                MATIC_BANANA_APE_LP: '0x034293F21F1cCE5908BC605CE5850dF2b1059aC0', //apeswap pid = 0
        }
}

const routers = {
        polygon: {
                SUSHISWAP_ROUTER: '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
                APESWAP_ROUTER: '0xC0788A3aD43d79aa53B09c2EaCc313A787d1d607',
                JETSWAP_ROUTER: '0x5C6EC38fb0e2609672BDf628B1fD605A523E5923',
                QUICKSWAP_ROUTER: '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff',
                POLYCAT_ROUTER: '0x94930a328162957ff1dd48900af67b5439336cbd',
        }
}

module.exports = {
        accounts,
        tokens,
        masterChefs,
        lps,
        routers
}

