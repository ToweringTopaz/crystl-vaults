// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBase.sol";

//For calling the earn function
abstract contract VaultHealerFees is VaultHealerBase {
    using BitMaps for BitMaps.BitMap;
    using Vault for Vault.Fee;

    bytes32 public constant FEE_SETTER = keccak256("FEE_SETTER");

    BitMaps.BitMap internal _overrideDefaultEarnFees; // strategy's fee config doesn't change with the vaulthealer's default
    BitMaps.BitMap private _overrideDefaultWithdrawFee;
    Vault.Fees public defaultEarnFees; // Settings which are generally applied to all strategies
    Vault.Fee public defaultWithdrawFee; //withdrawal fee is set separately from earn fees

    event SetDefaultEarnFees(Vault.Fees _earnFees);
    event SetDefaultWithdrawFee(Vault.Fee _withdrawFee);
    event SetEarnFees(uint vid, Vault.Fees _earnFees);
    event SetWithdrawFee(uint vid, Vault.Fee _withdrawFee);
    event ResetEarnFees(uint vid);
    event ResetWithdrawFee(uint vid);

    constructor(address _owner, Vault.Fees memory _earnFees, Vault.Fee memory _withdrawFee) {
        _setupRole(FEE_SETTER, _owner);

        Vault.check(_earnFees);
        Vault.check(_withdrawFee);
        defaultEarnFees = _earnFees;
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultEarnFees(_earnFees);
        emit SetDefaultWithdrawFee(_withdrawFee);
    }

    function getEarnFees(uint _vid) internal view returns (Vault.Fees storage) {
        return _overrideDefaultEarnFees.get(_vid) ? _vaultInfo[_vid].earnFees : defaultEarnFees;
    }

    function getWithdrawFee(uint _vid) internal view returns (Vault.Fee storage) {
        return _overrideDefaultWithdrawFee.get(_vid) ? _vaultInfo[_vid].withdrawFee : defaultWithdrawFee;
    }

     function setDefaultWithdrawFee(Vault.Fee calldata _withdrawFee) external onlyRole(FEE_SETTER) {
        Vault.check(_withdrawFee);
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultWithdrawFee(_withdrawFee);
    }   

    function setEarnFees(uint _vid, Vault.Fees calldata _earnFees) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.set(_vid);
        _vaultInfo[_vid].earnFees = _earnFees;
        emit SetEarnFees(_vid, _earnFees);
    }
    function resetEarnFees(uint _vid) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.unset(_vid);
        delete _vaultInfo[_vid].earnFees;
        emit ResetEarnFees(_vid);
    }
    
    function setDefaultEarnFees(Vault.Fees calldata _earnFees) external onlyRole(FEE_SETTER) {
        defaultEarnFees = _earnFees;
        emit SetDefaultEarnFees(_earnFees);
    }   

    function setWithdrawFee(uint _vid, Vault.Fee calldata _withdrawFee) external onlyRole(FEE_SETTER) {
        _overrideDefaultWithdrawFee.set(_vid);
        _vaultInfo[_vid].withdrawFee = _withdrawFee;
        emit SetWithdrawFee(_vid, _withdrawFee);
    }

    function resetWithdrawFee(uint _vid) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.unset(_vid);   
         emit ResetWithdrawFee(_vid);
    }


}