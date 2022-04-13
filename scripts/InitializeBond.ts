import { ethers, network } from "hardhat";
import { tokens, accounts, lps, routers } from "../configs/addresses";
import { advanceBlock, advanceBlockTo, advanceBlockWithNumber, setBalance, increaseTime, setERC20TokenBalance, getMaticPrice, getTokenPair } from "../test/utils";
const { WMATIC, CRYSTL, DAI } = tokens.polygon;
const { MATIC_CRYSTL_APE_LP } = lps.polygon;
const { APESWAP_ROUTER } = routers.polygon;
const { FEE_ADDRESS, BURN_ADDRESS, ZERO_ADDRESS } = accounts.polygon;

// Mumbai
// customTreasury ::  0xD61743e6cfb9BCB928FA7B1C72d9B8b23E5e1EdB
//     customBond ::  0xCED5BCa52aA6E79e5Ae5f895C03D716363482920
// -- Uninitialized
// customTreasury :: 0xfF91446fb4Cf95e58ea4D1C74509483cBac217bd
//     customBond :: 0x672C24da7ca5e3891a7d43d1EC19df33EeE2fdFb

// Mainnet
// customTreasury ::  0xf1dF8De68170009d0dDec516A249035FfbCA636E
//     customBond ::  0xfF91446fb4Cf95e58ea4D1C74509483cBac217bd
// -- Uninitialized
// customTreasury :: 0x766C2eb894BFe639d9c0aB9ba9E35243604fFcb8
//     customBond :: 0xcEb2701556A808D6cB9C468A1261840D87686fef

async function main() {

    let CustomTreasury: any;
    let CustomBond: any;
    let customTreasury: any;
    let customBond: any;

    const [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());


    CustomTreasury = await ethers.getContractFactory("CustomTreasury");
    CustomBond = await ethers.getContractFactory("CustomBond");


    // ****** Test DATA ******
    // MODIFY DATA if for real deployments according to blockchain status

    let vestingTerm = 38000 * 7; // Polygon - average 38000 in a day * 7; Ethereum - 46200: 7 days
    let minimumPrice = 10000;
    let initialCV = 250000;
    let maxPayout = 5000;
    let maxDebt = "100000000000000000000000000"; // 1e26
    let initialDebt = "660000000000000000000"; // 66e19

    customTreasury = await CustomTreasury.deploy(
        CRYSTL,         //address _payoutToken,  todo - what should this be? we bond crystl and pay out in?
        deployer.address,  //address _initialOwner
    );
    console.log("Deployed CustomTreasury :: ", customTreasury.address);

    customBond = await CustomBond.deploy(
        customTreasury.address, //address _customTreasury, 
        MATIC_CRYSTL_APE_LP,    //address _principalToken, CRYSTL-CRO LP
        deployer.address,          //address _initialOwner
    );
    console.log("Deployed CustomBond :: ", customBond.address);

    // user1's balance of principal token is 457,342114826036968505

    await customTreasury.toggleBondContract(customBond.address);

    await customBond.setBondTerms(0, vestingTerm); //PARAMETER = { 0: VESTING, 1: PAYOUT, 3: DEBT }

    await customBond.initializeBond(
        initialCV,                    //uint _controlVariable, 
        vestingTerm,                  //uint _vestingTerm, 7 days
        minimumPrice,                 //1351351, uint _minimumPrice,
        maxPayout,                    //uint _maxPayout, 100e9
        maxDebt,                      //uint _maxDebt, 
        initialDebt,                  //uint _initialDebt
    );

    console.log("Deployment & Initialization Done.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
