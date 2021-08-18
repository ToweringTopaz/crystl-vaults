const VaultHealer = artifacts.require("VaultHealer");
const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");

module.exports = async function(deployer) {
    // Contracts
    const BARBER_MASTERCHEF = '0xC6Ae34172bB4fC40c49C3f53badEbcE3Bb8E6430';
    const APESWAP_ROUTER = '0xC0788A3aD43d79aa53B09c2EaCc313A787d1d607';

    // Tokens 
    const CRYSTL = '0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64';
    const WMATIC = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270';
    const WETH = '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619';
    const USDC = '0x2791bca1f2de4661ed88a30c99a7a9449aa84174';
    const DAI = '0x8f3cf7ad23cd3cadbd9735aff958023239c6a063';
    const HAIR = '0x100A947f51fA3F1dcdF97f3aE507A72603cAE63C';
    const BANANA = '0x5d47baba0d66083c52009271faf3f50dcc01023c';

    // Ape LPs for Barbershop
    MATIC_CRYSTL_APE_LP = '0xb8e54c9ea1616beebe11505a419dd8df1000e02a'; // pid = 9
    BANANA_ETH_APE_LP = '0x44b82c02F404Ed004201FB23602cC0667B1D011e'; // pid = 2
    MATIC_HAIR_APE_LP = '0x491c17b1b9aa867f3a7a480baffc0721d59a7393'; // pid = 1
    HAIR_USDC_APE_LP = '0xb394009787c2d0cb5b45d06e401a39648e21d681'; // pid = 8

    // Instances
    let vaultHealerInstance;
    let barberMaticCrystlInstance;
    let barberBananaEthInstance;
    let barberMaticHairInstance;
    let barberHairUsdcInstance;

    /*
    1. Deploy VaultHealer
    */
    deployer.deploy(VaultHealer).then((instance) => {
        vaultHealerInstance = instance;
    }).then(()=> {
        /*
        2a. Deploy StrategyMasterHealer for MATIC-CRYSTL on Barber
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            BARBER_MASTERCHEF, // address _masterchefAddress
            APESWAP_ROUTER, // address _uniRouterAddress
            9, // uint256 _pid 
            MATIC_CRYSTL_APE_LP, // address _wantAddress
            HAIR, // address _earnedAddress
            1, // uint256 tolerance
            [HAIR, WMATIC], // address[] memory _earnedToWmaticPath
            [HAIR, USDC], // address[] memory _earnedToUsdcPath
            [HAIR, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [HAIR, WMATIC], // address[] memory _earnedToToken0Path
            [HAIR, WMATIC, CRYSTL], // address[] memory _earnedToToken1Path
            [WMATIC, HAIR], // address[] memory _token0ToEarnedPath
            [CRYSTL, WMATIC, HAIR], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        2b. Add Deployed Instance for MATIC-CRYSTL Strategy
        */
        barberMaticCrystlInstance = instance;
        return vaultHealerInstance.addPool(barberMaticCrystlInstance.address);
    }).then(()=> {
        /*
        3a. Deploy StrategyMasterHealer for BANANA-ETH on Barber
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            BARBER_MASTERCHEF, // address _masterchefAddress
            APESWAP_ROUTER, // address _uniRouterAddress
            2, // uint256 _pid --> BANANA-ETH
            BANANA_ETH_APE_LP, // address _wantAddress
            HAIR, // address _earnedAddress
            1, // uint256 tolerance
            [HAIR, WMATIC], // address[] memory _earnedToWmaticPath
            [HAIR, USDC], // address[] memory _earnedToUsdcPath
            [HAIR, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [HAIR, WMATIC, BANANA], // address[] memory _earnedToToken0Path
            [HAIR, WMATIC, WETH], // address[] memory _earnedToToken1Path
            [BANANA, WMATIC, HAIR], // address[] memory _token0ToEarnedPath
            [WETH, WMATIC, HAIR], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        3b. Add Deployed Instance for BANANA-ETH Strategy
        */
        barberBananaEthInstance = instance;
        return vaultHealerInstance.addPool(barberBananaEthInstance.address);
    }).then(()=> {
        /*
        4a. Deploy StrategyMasterHealer for MATIC-HAIR on Barber
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            BARBER_MASTERCHEF, // address _masterchefAddress
            APESWAP_ROUTER, // address _uniRouterAddress
            1, // uint256 _pid 
            MATIC_HAIR_APE_LP, // address _wantAddress
            HAIR, // address _earnedAddress
            1, // uint256 tolerance
            [HAIR, WMATIC], // address[] memory _earnedToWmaticPath
            [HAIR, USDC], // address[] memory _earnedToUsdcPath
            [HAIR, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [HAIR, WMATIC], // address[] memory _earnedToToken0Path
            [HAIR], // address[] memory _earnedToToken1Path
            [WMATIC, HAIR], // address[] memory _token0ToEarnedPath
            [HAIR], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        4b. Add Deployed Instance for MATIC-HAIR Strategy
        */
        barberMaticHairInstance = instance;
        return vaultHealerInstance.addPool(barberMaticHairInstance.address);
    }).then(()=> {
        /*
        5a. Deploy StrategyMasterHealer for HAIR-USDC on Barber
        */
        return deployer.deploy(
            StrategyMasterHealer,
            vaultHealerInstance.address, // address _vaultChefAddress
            BARBER_MASTERCHEF, // address _masterchefAddress
            APESWAP_ROUTER, // address _uniRouterAddress
            8, // uint256 _pid 
            HAIR_USDC_APE_LP, // address _wantAddress
            HAIR, // address _earnedAddress
            1, // uint256 tolerance
            [HAIR, WMATIC], // address[] memory _earnedToWmaticPath
            [HAIR, USDC], // address[] memory _earnedToUsdcPath
            [HAIR, WMATIC, CRYSTL], // address[] memory _earnedToFishPath
            [HAIR], // address[] memory _earnedToToken0Path
            [HAIR, USDC], // address[] memory _earnedToToken1Path
            [HAIR], // address[] memory _token0ToEarnedPath
            [USDC, HAIR], // address[] memory _token1ToEarnedPath
        )
    }).then((instance)=> {
        /*
        5b. Add Deployed Instance for HAIR-USDC Strategy
        */
        barberHairUsdcInstance = instance;
        return vaultHealerInstance.addPool(barberHairUsdcInstance.address);
    }).then(()=> {
        console.table({
            VaultHealer: vaultHealerInstance.address,
            BarbershopMaticCrystlStrategy: barberMaticCrystlInstance.address,
            BarbershopBananaEthStrategy: barberBananaEthInstance.address,
            BarbershopMaticHairStrategy: barberMaticHairInstance.address,
            BarbershopHairUsdcStrategy: barberHairUsdcInstance.address
        })
    });
};