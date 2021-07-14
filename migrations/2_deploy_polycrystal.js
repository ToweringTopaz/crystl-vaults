const VaultHealer = artifacts.require("VaultHealer");
const StrategyMasterHealer = artifacts.require("StrategyMasterHealer");

module.exports = async function(deployer, network) {
    const MASTER_HEALER = '0xeBCC84D2A73f0c9E23066089C6C24F4629Ef1e6d';
    const CRYSTL = '0x76bf0c28e604cc3fe9967c83b3c3f31c213cfe64' 
    const MATIC = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270';
    const CRYSTL_MATIC = '0xb8e54c9ea1616beebe11505a419dd8df1000e02a'; 
    const BANANA_ETH = '0x44b82c02f404ed004201fb23602cc0667b1d011e';
    const BANANA = '0x5d47baba0d66083c52009271faf3f50dcc01023c';
    const ETH = '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619';
    
    let vaultHealerInstance;
    let crystalMaticStrategyInstance;
    let bananaEthStrategyInstance;

    /*
    1. Deploy VaultHealer
    */
    deployer.deploy(VaultHealer).then((instance) => {
        vaultHealerInstance = instance;
    }).then(()=> {
        /*
        2. Deploy StrategyMasterHealer for CRYSTL-MATIC
        */
        return deployer.deploy(
            StrategyMasterHealer, 
            vaultHealerInstance.address, 
            MASTER_HEALER, 
            1, 
            CRYSTL_MATIC, 
            CRYSTL, 
            [CRYSTL], 
            [CRYSTL, MATIC], 
            [CRYSTL], 
            [MATIC, CRYSTL], 
            [CRYSTL]
        )
    }).then((instance)=> {
        /*
        3. Add Deployed Instance for CRYSTL-MATIC Strategy
        */
        crystalMaticStrategyInstance = instance;
        return vaultHealerInstance.addPool(crystalMaticStrategyInstance.address);
    }).then(()=> {
        /*
        4. Deploy StrategyMasterHealer for BANANA-ETH
        */
        return deployer.deploy(
            StrategyMasterHealer, 
            vaultHealerInstance.address, 
            MASTER_HEALER, 
            3, 
            BANANA_ETH, 
            CRYSTL, 
            [CRYSTL], 
            [CRYSTL, MATIC, BANANA], 
            [CRYSTL, MATIC, ETH], 
            [BANANA, MATIC, CRYSTL], 
            [ETH, MATIC, CRYSTL]
        )
    }).then((instance)=> {
        /*
        5. Add Deployed Instance for BANANA-ETH Strategy
        */
        bananaEthStrategyInstance = instance;
        return vaultHealerInstance.addPool(bananaEthStrategyInstance.address);
    }).then(()=> {
        console.table({
            VaultHealer: vaultHealerInstance.address,
            CrystlMaticStrategy: crystalMaticStrategyInstance.address,
            BananaEthStrategy: bananaEthStrategyInstance.address,
        })
    });
};