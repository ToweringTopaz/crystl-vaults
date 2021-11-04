const CronaPriceGetter = artifacts.require("CronaPriceGetter");

module.exports = async function (deployer, network) {
    await deployer.deploy(
        CronaPriceGetter
    )
    const CronaPriceGetterInstance = await CronaPriceGetter.deployed();

    console.table({
        CronaPriceGetterLibrary: CronaPriceGetterInstance.address,
    })
};