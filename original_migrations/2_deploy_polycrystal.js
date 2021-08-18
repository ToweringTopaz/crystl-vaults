const VaultHealer = artifacts.require("VaultHealer");
const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");

// Vaults to add
// Barbershop BANANA-ETH
// Barbershop HAIR-MATIC

module.exports = async function(deployer) {
    // Contracts
    const DINO_MASTERCHEF = '0x1948abC5400Aa1d72223882958Da3bec643fb4E5';
    const QUICKSWAP_ROUTER = '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff';
    const JETSWAP_MASTERCHEF = '0x4e22399070aD5aD7f7BEb7d3A7b543e8EcBf1d85';
    const JETSWAP_ROUTER = '0x5C6EC38fb0e2609672BDf628B1fD605A523E5923';
    const BARBER_MASTERCHEF = '0xC6Ae34172bB4fC40c49C3f53badEbcE3Bb8E6430';
    const APESWAP_ROUTER = '0xC0788A3aD43d79aa53B09c2EaCc313A787d1d607';
    const HAIR = '0x100A947f51fA3F1dcdF97f3aE507A72603cAE63C';
    const BANANA = '0x5d47baba0d66083c52009271faf3f50dcc01023c';

    // Tokens 
    const CRYSTL = '0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64';
    const WMATIC = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270';
    const WETH = '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619';
    const DINO = '0xAa9654BECca45B5BDFA5ac646c939C62b527D394';
    const USDC = '0x2791bca1f2de4661ed88a30c99a7a9449aa84174';
    const USDT = '0xc2132d05d31c914a87c6611c10748aeb04b58e8f';
    const DAI = '0x8f3cf7ad23cd3cadbd9735aff958023239c6a063';
    const PWINGS = '0x845E76A8691423fbc4ECb8Dd77556Cb61c09eE25';
    const WBTC = '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6';

    // QuickSwap LPs (for DinoSwap)
    const WMATIC_WETH_QUICK_LP = '0xadbF1854e5883eB8aa7BAf50705338739e558E5b'; // pid = 6
    const USDC_WETH_QUICK_LP = '0x853ee4b2a13f8a742d64c8f088be7ba2131f670d'; // pid = 7
    const USDC_USDT_QUICK_LP = '0x2cf7252e74036d1da831d11089d326296e64a728'; // pid = 8

    // JetSwap LPs
    const WBTC_USDT_JET_LP = '0x7641d6b873877007697d526ef3c50908779a6993'; // pid = 12
    const WBTC_WETH_JET_LP = '0x173e90f2a94af3b075deec7e64df4d70efb4ac3d'; // pid = 14
    const USDC_DAI_JET_LP = '0x4a53119dd905fd39ccc532c68e69505dfb47fc2c'; // pid = 16

    // ApeSwap LPs
    BANANA_ETH_APE_LP = '0x44b82c02F404Ed004201FB23602cC0667B1D011e'; // pid = 2

    // Instances
    let vaultHealerInstance;
    let dinoSwapMaticEthInstance;
    let dinoSwapUsdcEthInstance; 
    let dinoSwapUsdcUsdtInstance; 
    let jetSwapBtcUsdtInstance;
    let jetSwapBtcEthInstance; 
    let jetSwapUsdcDaiInstance;
    let barberBananaEthInstance;

    /*
    1. Deploy VaultHealer
    */
    deployer.deploy(VaultHealer).then((instance) => {
        vaultHealerInstance = instance;
    }).then(()=> {
        /*
        2a. Deploy StrategyMasterHealer for MATIC-ETH on DinoSwap
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            DINO_MASTERCHEF, // address _masterchefAddress
            QUICKSWAP_ROUTER, // address _uniRouterAddress
            6, // uint256 _pid
            WMATIC_WETH_QUICK_LP, // address _wantAddress
            DINO, // address _earnedAddress
            [DINO, WETH, WMATIC], // address[] memory _earnedToWmaticPath
            [DINO, WETH, USDC], // address[] memory _earnedToUsdcPath
            [DINO, WETH, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [DINO, WETH, WMATIC], // address[] memory _earnedToToken0Path
            [DINO, WETH], // address[] memory _earnedToToken1Path
            [WMATIC, WETH, DINO], // address[] memory _token0ToEarnedPath
            [WETH, DINO], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        2b. Add Deployed Instance for WETH-MATIC Strategy
        */
        dinoSwapMaticEthInstance = instance;
        return vaultHealerInstance.addPool(dinoSwapMaticEthInstance.address);
    }).then(()=> {
        /*
        3a. Deploy StrategyMasterHealer for USDC-ETH on DinoSwap
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            DINO_MASTERCHEF, // address _masterchefAddress
            QUICKSWAP_ROUTER, // address _uniRouterAddress
            7, // uint256 _pid
            USDC_WETH_QUICK_LP, // address _wantAddress
            DINO, // address _earnedAddress
            [DINO, WETH, WMATIC], // address[] memory _earnedToWmaticPath
            [DINO, WETH, USDC], // address[] memory _earnedToUsdcPath
            [DINO, WETH, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [DINO, WETH, USDC], // address[] memory _earnedToToken0Path
            [DINO, WETH], // address[] memory _earnedToToken1Path
            [USDC, WETH, DINO], // address[] memory _token0ToEarnedPath
            [WETH, DINO], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        3b. Add Deployed Instance for USDC-ETH Strategy
        */
        dinoSwapUsdcEthInstance = instance;
        return vaultHealerInstance.addPool(dinoSwapUsdcEthInstance.address);
    }).then(()=> {
        /*
        4a. Deploy StrategyMasterHealer for USDC-USDT on DinoSwap
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            DINO_MASTERCHEF, // address _masterchefAddress
            QUICKSWAP_ROUTER, // address _uniRouterAddress
            8, // uint256 _pid
            USDC_USDT_QUICK_LP, // address _wantAddress
            DINO, // address _earnedAddress
            [DINO, WETH, WMATIC], // address[] memory _earnedToWmaticPath
            [DINO, WETH, USDC], // address[] memory _earnedToUsdcPath
            [DINO, WETH, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [DINO, WETH, USDC], // address[] memory _earnedToToken0Path
            [DINO, WETH, USDT], // address[] memory _earnedToToken1Path
            [USDC, WETH, DINO], // address[] memory _token0ToEarnedPath
            [USDT, WETH, DINO], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        4b. Add Deployed Instance for USDC-USDT Strategy
        */
        dinoSwapUsdcUsdtInstance = instance;
        return vaultHealerInstance.addPool(dinoSwapUsdcUsdtInstance.address);
    }).then(()=> {
        /*
        5a. Deploy StrategyMasterHealer for BTC-USDT on JetSwap
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            JETSWAP_MASTERCHEF, // address _masterchefAddress
            JETSWAP_ROUTER, // address _uniRouterAddress
            12, // uint256 _pid
            WBTC_USDT_JET_LP, // address _wantAddress
            PWINGS, // address _earnedAddress
            [PWINGS, WMATIC], // address[] memory _earnedToWmaticPath
            [PWINGS, WMATIC, USDC], // address[] memory _earnedToUsdcPath
            [PWINGS, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [PWINGS, WMATIC, USDT, WBTC], // address[] memory _earnedToToken0Path
            [PWINGS, WMATIC, USDT], // address[] memory _earnedToToken1Path
            [WBTC, USDT, WMATIC, PWINGS], // address[] memory _token0ToEarnedPath
            [USDT, WMATIC, PWINGS], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        5b. Add Deployed Instance for ETH-BTC strategy
        */
        jetSwapBtcUsdtInstance = instance;
        return vaultHealerInstance.addPool(jetSwapBtcUsdtInstance.address);
    }).then(()=> {
        /*
        6a. Deploy StrategyMasterHealer for BTC-ETH on JetSwap
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            JETSWAP_MASTERCHEF, // address _masterchefAddress
            JETSWAP_ROUTER, // address _uniRouterAddress
            14, // uint256 _pid
            WBTC_WETH_JET_LP, // address _wantAddress
            PWINGS, // address _earnedAddress
            [PWINGS, WMATIC], // address[] memory _earnedToWmaticPath
            [PWINGS, WMATIC, USDC], // address[] memory _earnedToUsdcPath
            [PWINGS, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [PWINGS, WMATIC, USDT, WBTC], // address[] memory _earnedToToken0Path
            [PWINGS, WMATIC, WETH], // address[] memory _earnedToToken1Path
            [WBTC, USDT, WMATIC, PWINGS], // address[] memory _token0ToEarnedPath
            [WETH, WMATIC, PWINGS], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        6b. Add Deployed Instance for BTC-ETH strategy
        */
        jetSwapBtcEthInstance = instance;
        return vaultHealerInstance.addPool(jetSwapBtcEthInstance.address);
    }).then(()=> {
        /*
        7a. Deploy StrategyMasterHealer for USDC-DAI on JetSwap
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            JETSWAP_MASTERCHEF, // address _masterchefAddress
            JETSWAP_ROUTER, // address _uniRouterAddress
            16, // uint256 _pid
            USDC_DAI_JET_LP, // address _wantAddress
            PWINGS, // address _earnedAddress
            [PWINGS, WMATIC], // address[] memory _earnedToWmaticPath
            [PWINGS, WMATIC, USDC], // address[] memory _earnedToUsdcPath
            [PWINGS, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [PWINGS, WMATIC, USDC], // address[] memory _earnedToToken0Path
            [PWINGS, WMATIC, USDC, DAI], // address[] memory _earnedToToken1Path
            [USDC, WMATIC, PWINGS], // address[] memory _token0ToEarnedPath
            [DAI, USDC, WMATIC, PWINGS], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        7b. Add Deployed Instance for USDC-DAI strategy
        */
        jetSwapUsdcDaiInstance = instance;
        return vaultHealerInstance.addPool(jetSwapUsdcDaiInstance.address);
    }).then(()=> {
        /*
        8a. Deploy StrategyMasterHealer for BANANA-ETH on Barbershop
        */
        return deployer.deploy(
            StrategyMasterHealer,
            POLYCRYSTAL_VAULT_CHEF, // address _vaultChefAddress
            BARBER_MASTERCHEF, // address _masterchefAddress
            APESWAP_ROUTER, // address _uniRouterAddress
            2, // uint256 _pid --> BANANA-ETH
            BANANA_ETH_APE_LP, // address _wantAddress
            HAIR, // address _earnedAddress
            [HAIR, WMATIC], // address[] memory _earnedToWmaticPath
            [HAIR, WMATIC, DAI, USDC], // address[] memory _earnedToUsdcPath
            [HAIR, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [HAIR, WMATIC, BANANA], // address[] memory _earnedToToken0Path
            [HAIR, WMATIC, WETH], // address[] memory _earnedToToken1Path
            [BANANA, WMATIC, HAIR], // address[] memory _token0ToEarnedPath
            [WETH, WMATIC, HAIR], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        8b. Add Deployed Instance for BANANA-ETH strategy
        */
        barberBananaEthInstance = instance;
        return vaultHealerInstance.addPool(barberBananaEthInstance.address);
    }).then(()=> {
        console.table({
            VaultHealer: vaultHealerInstance.address,
            DinoSwapMaticEthStrategy: dinoSwapMaticEthInstance.address,
            DinoSwapUsdcEthStrategy: dinoSwapUsdcEthInstance.address,
            DinoSwapUsdcUsdtStrategy: dinoSwapUsdcUsdtInstance.address,
            JetSwapBtcUsdtStrategy: jetSwapBtcUsdtInstance.address,
            JetSwapBtcEthStrategy: jetSwapBtcEthInstance.address,
            JetSwapUsdcDaiStrategy: jetSwapUsdcDaiInstance.address,
            BarbershopBananaEthStreatgy: barberBananaEthInstance.address
        })
    });
};