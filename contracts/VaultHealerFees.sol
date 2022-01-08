// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBase.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";

//For calling the earn function
abstract contract VaultHealerFees is VaultHealerBase {
    using BitMaps for BitMaps.BitMap;
    using LibVaultConfig for VaultFee;

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
        LibVaultConfig.check(_withdrawFee);
        defaultEarnFees = _earnFees;
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultEarnFees(_earnFees);
        emit SetDefaultWithdrawFee(_withdrawFee);
    }

    function getEarnFees(uint _vid) internal view returns (VaultFees storage) {
        return _overrideDefaultEarnFees.get(_vid) ? _vaultInfo[_vid].earnFees : defaultEarnFees;
    }

    function getWithdrawFee(uint _vid) internal view returns (VaultFee storage) {
        return _overrideDefaultWithdrawFee.get(_vid) ? _vaultInfo[_vid].withdrawFee : defaultWithdrawFee;
    }

     function setDefaultWithdrawFee(VaultFee calldata _withdrawFee) external onlyRole(FEE_SETTER) {
        LibVaultConfig.check(_withdrawFee);
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