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

    console.log("Deployment Done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

