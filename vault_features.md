# Vault features

There are three types of vault strategies currently available, and more can be created as needed with little modification required, due to the contracts' inheritance structure.

All of the vault options have a default 0.1% deposit fee (depositFeeRate), which can be increased to a maximum of 2% (DEPOSIT_FEE_MAX). The fee is taken from the principal amount of deposit and sent directly to a depositFeeReceiver address.

 Before their earnings are compounded, the vaults also take a default 2% performance fee (buybackRate) which is used to purchase CRYSTL. This CRYSTL is sent to an address (buybackReceiver) which can be a burn address, or it can be  a dev wallet or a contract which might feed the CRYSTL back to investors. All of these settings are configurable in the BaseBaseStrategy contract's setSettings() function.
 
 The strategy contracts cannot operate independently of a VaultHealer (or VaultMonolith, which inherits from VaultHealer), and generally the VaultHealer is the contract most relevant to the user interface. The owner of each strategy is set to the VaultHealer, and vital functions like deposit(), withdraw(), and earn() can only be called via VaultHealer.
 
 The VaultMonolith child contract must be used instead of VaultHealer if using Crystallizer and CrystalCore.

## Important external strategy functions

wantLockedTotal() returns (uint256) total amount of the strategy's farming tokens, such as LP tokens
	
paused() returns (bool) showing whether the governor has emergency-withdrawn paused the vault

buybackRate() returns (uint256) the amount of earnings which are swapped to crystl and sent away

isCrystalCore() and isCrystallizer() return (bool) showing whether the vault is either of those types of strategy, explained later.

Most of the time, there is no need for users to directly interact with the strategies.

## StrategyMasterHealer

These strategies are compatible with MasterHealer/MasterChef contracts like the one at PolyCrystal, ApeSwap, and SushiSwap. Users deposit LP tokens, which the contract then stakes in the MasterHealer to earn CRYSTL or a similar token. When the compounding earn() function is triggered, the earned CRYSTL is gathered, split in two (minus the buyback fee), and swapped to each half of the liquidity pair. The original investment tokens grow in number over time.

Generally we would rather investors hold and stake their CRYSTL rather than sell it all, so we have an alternative.

## Crystallizer strategies

These function similarly to StrategyMasterHealer, but instead of compounding to more LP tokens, their earn() function keeps CRYSTL or converts a different earned token to CRYSTL. After the earn() function completes, the VaultMonolith deposits the CRYSTL into CrystalCore.

This is the same concept as ApeRocket's banana maximizer. With a crystallizer, the principal investment does not normally change over time. The earnings portion grows separately and generally much faster due to the CRYSTL to CRYSTL pool's high APR.

## CrystalCore strategy

This strategy is optimized for the CRYSTL to CRYSTL pool. It simply accumulates and restakes CRYSTL. Users and crystallizer strategies alike may deposit CRYSTL to this via VaultMonolith.

