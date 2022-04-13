# PolyCrystal Bonding
The official repository of PolyCrystal.Finance Bonding code ❤️🔮

Use them now at [PolyCrystal.Finance/Vaults](https://polycrystal.finance/vaults)!

## Contracts

### CustomBond
The primary contract that handles bonding & bonding mechanism is the **CustomBond** contract. The core contract of bonding.

### CustomTreasury
The treasury contract that takes CRYSTL tokens for bond sale. **CustomTreasury** is the primary contract that works as treasury for bond market.

## Commands

### Bonding Contract Test
Test Command
```
npx hardhat test
```
100% Test Coverage

### Bonding Market Adjustment
Adjustment Command
```
npx ts-node --files scripts/AdjustBond.ts <customBond Addr> <customTreasury Addr>
```

### Deploy & Initialize Bonding Contracts
Deployment & Initialization Command
```
npx hardhat run scripts/InitializeBond.ts --network <polygon | mumbai>
```
*Disclaimer : To change bond market initialization variables modify **InitializeBond.ts***

### Deploy Bonding Contracts
Deployment Command
```
npx hardhat run scripts/DeployBond.ts --network <polygon | mumbai>
```

## Variable Alteration
1. `Vesting Term` : 46200 -> 3800 * 7

## Test Deployments
```
- Mumbai -
customTreasury ::  0xD61743e6cfb9BCB928FA7B1C72d9B8b23E5e1EdB
    customBond ::  0xCED5BCa52aA6E79e5Ae5f895C03D716363482920
-- Uninitialized
customTreasury :: 0xfF91446fb4Cf95e58ea4D1C74509483cBac217bd
    customBond :: 0x672C24da7ca5e3891a7d43d1EC19df33EeE2fdFb

- Mainnet -
customTreasury ::  0xf1dF8De68170009d0dDec516A249035FfbCA636E
    customBond ::  0xfF91446fb4Cf95e58ea4D1C74509483cBac217bd
-- Uninitialized
customTreasury :: 0x766C2eb894BFe639d9c0aB9ba9E35243604fFcb8
    customBond :: 0xcEb2701556A808D6cB9C468A1261840D87686fef
```