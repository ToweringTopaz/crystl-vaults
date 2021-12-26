// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBase.sol";

//For calling the earn function
abstract contract VaultHealerFees is VaultHealerBase {
    using BitMaps for BitMaps.BitMap;

    bytes32 public constant FEE_SETTER = keccak256("FEE_SETTER");

    BitMaps.BitMap internal _overrideDefaultEarnFees; // strategy's fee config doesn't change with the vaulthealer's default
    BitMaps.BitMap private _overrideDefaultWithdrawFee;
    VaultFees public defaultEarnFees; // Settings which are generally applied to all strategies
    VaultFee public defaultWithdrawFee; //withdrawal fee is set separately from earn fees

    event SetDefaultEarnFees(VaultFees _earnFees);
    event SetDefaultWithdrawFee(VaultFee _withdrawFee);
    event SetEarnFees(uint vid, VaultFees _earnFees);
    event SetWithdrawFee(uint vid, VaultFee _withdrawFee);
    event ResetEarnFees(uint vid);
    event ResetWithdrawFee(uint vid);

    constructor(address _owner, VaultFees memory _earnFees, VaultFee memory _withdrawFee) {
        _setupRole(FEE_SETTER, _owner);

        LibVaultConfig.check(_earnFees);
        defaultEarnFees = _earnFees;
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultEarnFees(_earnFees);
    }


    function getEarnFees(uint _vid) public view returns (VaultFees memory) {
        VaultInfo storage vault = _vaultInfo[_vid];
        if (overrideDefaultEarnFees(_vid)) 
            return vault.earnFees;
        else
            return defaultEarnFees;
    }
    
    function overrideDefaultEarnFees(uint vid) public view returns (bool) { // strategy's fee config doesn't change with the vaulthealer's default
        return _overrideDefaultEarnFees.get(vid);
    }
    function overrideDefaultWithdrawFee(uint vid) public view returns (bool) {
        return _overrideDefaultWithdrawFee.get(vid);
    }

     function setDefaultWithdrawFee(VaultFee calldata _withdrawFee) external onlyRole(FEE_SETTER) {
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultWithdrawFee(_withdrawFee);
    }   

    function setEarnFees(uint _vid, VaultFees calldata _earnFees) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.set(_vid);
        _vaultInfo[_vid].earnFees = _earnFees;
        emit SetEarnFees(_vid, _earnFees);
    }
    function resetEarnFees(uint _vid) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.unset(_vid);
        delete _vaultInfo[_vid].earnFees;
        emit ResetEarnFees(_vid);
    }
    
    function getWithdrawFee(uint _vid) public view returns (VaultFee memory) {
        return _vaultInfo[_vid].withdrawFee;
    }
    function setDefaultEarnFees(VaultFees calldata _earnFees) external onlyRole(FEE_SETTER) {
        defaultEarnFees = _earnFees;
        emit SetDefaultEarnFees(_earnFees);
    }   

    function setWithdrawFee(uint _vid, VaultFee calldata _withdrawFee) external onlyRole(FEE_SETTER) {
        _overrideDefaultWithdrawFee.set(_vid);
        _vaultInfo[_vid].withdrawFee = _withdrawFee;
        emit SetWithdrawFee(_vid, _withdrawFee);
    }

    function resetWithdrawFee(uint _vid) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.unset(_vid);   
         emit ResetWithdrawFee(_vid);
    }


}