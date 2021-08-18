const VaultHealer = artifacts.require("VaultHealer");
const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");

module.exports = async function(deployer) {
    // Contracts
    const BARBER_MASTERCHEF = '0xC6Ae34172bB4fC40c49C3f53badEbcE3Bb8E6430';
    const APESWAP_ROUTER = '0xC0788A3aD43d79aa53B09c2EaCc313A787d1d607';
    const VAULT_HEALER = '0x0192eb09c31ded57ee77dbb9856ee75b19fb47ef';

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
    const HAIR = '0x100A947f51fA3F1dcdF97f3aE507A72603cAE63C';
    const BANANA = '0x5d47baba0d66083c52009271faf3f50dcc01023c';

    HAIR_USDC_APE_LP = '0xb394009787c2d0cb5b45d06e401a39648e21d681'; // pid = 8

    deployer.deploy(
        StrategyMasterHealer,
        VAULT_HEALER, // address _vaultChefAddress
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
    ).then((instance) => {
        console.table({
            Strategy: instance.address
        })
    });
};