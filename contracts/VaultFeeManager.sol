// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./interfaces/IVaultFeeManager.sol";

contract VaultFeeManager is IVaultFeeManager {
    using BitMaps for BitMaps.BitMap;
    using Fee for *;

    bytes32 constant FEE_SETTER = keccak256("FEE_SETTER");
    address constant public TX_ORIGIN = address(bytes20(keccak256("TX_ORIGIN"))); // if this address is used for earn fee, substitute tx.origin to pay the account providing the gas

    IAccessControl immutable public vaultHealer;

    mapping(uint256 => Fee.Data) withdrawFee;
    mapping(uint256 => Fee.Data[3]) earnFees;

    BitMaps.BitMap internal _overrideDefaultEarnFees; // strategy's fee config doesn't change with the vaulthealer's default
    BitMaps.BitMap private _overrideDefaultWithdrawFee;
    Fee.Data[3] public defaultEarnFees; // Settings which are generally applied to all strategies
    Fee.Data public defaultWithdrawFee; //withdrawal fee is set separately from earn fees

    event SetDefaultEarnFees(Fee.Data[3] _earnFees);
    event SetDefaultWithdrawFee(Fee.Data _withdrawFee);
    event SetEarnFees(uint vid, Fee.Data[3] _earnFees);
    event SetWithdrawFee(uint vid, Fee.Data _withdrawFee);
    event ResetEarnFees(uint vid);
    event ResetWithdrawFee(uint vid);

    constructor(address _vaultHealer, address withdrawReceiver, uint16 withdrawRate, address[3] memory earnReceivers, uint16[3] memory earnRates) {
        vaultHealer = IAccessControl(_vaultHealer);

        defaultEarnFees.set(earnReceivers, earnRates);
        defaultWithdrawFee = Fee.create(withdrawReceiver, withdrawRate);
        Fee.check(defaultEarnFees);
        Fee.check(defaultWithdrawFee);
        emit SetDefaultEarnFees(defaultEarnFees);
        emit SetDefaultWithdrawFee(defaultWithdrawFee);
    }

    modifier auth {
        require(vaultHealer.hasRole(FEE_SETTER, msg.sender), "!auth");
        _;
    }

    function getEarnFees(uint _vid) external view returns (Fee.Data[3] memory _fees) {
        _fees = _overrideDefaultEarnFees.get(_vid) ? earnFees[_vid] : defaultEarnFees;
        for (uint i; i < 3; i++) {
            if (_fees[i].receiver() == TX_ORIGIN)
                _fees[i] = Fee.create(tx.origin, _fees[i].rate());
        }
    }

    function getWithdrawFee(uint _vid) external view returns (address _receiver, uint16 _rate) {
        return _overrideDefaultWithdrawFee.get(_vid) ? withdrawFee[_vid].receiverAndRate() : defaultWithdrawFee.receiverAndRate();
    }

     function setDefaultWithdrawFee(address withdrawReceiver, uint16 withdrawRate) external auth {
        defaultWithdrawFee = Fee.create(withdrawReceiver, withdrawRate);
        Fee.check(defaultEarnFees);
        Fee.check(defaultWithdrawFee);
        emit SetDefaultEarnFees(defaultEarnFees);
        emit SetDefaultWithdrawFee(defaultWithdrawFee);
    }   

    function setEarnFees(uint _vid, Fee.Data[3] calldata _earnFees) external auth {
        _overrideDefaultEarnFees.set(_vid);
        earnFees[_vid] = _earnFees;
        emit SetEarnFees(_vid, _earnFees);
    }
    function resetEarnFees(uint _vid) external auth {
        _overrideDefaultEarnFees.unset(_vid);
        emit ResetEarnFees(_vid);
    }
    
    function setDefaultEarnFees(Fee.Data[3] calldata _earnFees) external auth {
        defaultEarnFees = _earnFees;
        emit SetDefaultEarnFees(_earnFees);
    }   

    function setWithdrawFee(uint _vid, address withdrawReceiver, uint16 withdrawRate) external auth {
        _overrideDefaultWithdrawFee.set(_vid);
        Fee.Data _withdrawFee = Fee.create(withdrawReceiver, withdrawRate);
        withdrawFee[_vid] = Fee.create(withdrawReceiver, withdrawRate);
        emit SetWithdrawFee(_vid, _withdrawFee);
    }

    function resetWithdrawFee(uint _vid) external auth {
        _overrideDefaultEarnFees.unset(_vid);   
         emit ResetWithdrawFee(_vid);
    }


}