// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/IAccessControl.sol";
import "./interfaces/IVaultHealer.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./interfaces/IVaultFeeManager.sol";
import "./libraries/Constants.sol";

contract VaultFeeManager is IVaultFeeManager {
    using BitMaps for BitMaps.BitMap;
    using Fee for *;

    address constant public TX_ORIGIN = address(bytes20(keccak256("TX_ORIGIN"))); // if this address is used for earn fee, substitute tx.origin to pay the account providing the gas

    IAccessControl immutable public vhAuth;

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

    constructor(address _vhAuth) {
        vhAuth = IAccessControl(_vhAuth);
    }

    modifier auth {
        _auth();
        _;
    }
    function _auth() internal view virtual {
        require(vhAuth.hasRole(FEE_SETTER, msg.sender), "!auth");
    }

    function getEarnFees(uint _vid) external view returns (Fee.Data[3] memory _fees) {
        _fees = _overrideDefaultEarnFees.get(_vid) ? earnFees[_vid] : defaultEarnFees;
        for (uint i; i < 3; i++) {
            if (_fees[i].receiver() == TX_ORIGIN)
                _fees[i] = Fee.create(tx.origin, _fees[i].rate());
        }
    }

    function getEarnFees(uint[] calldata _vids) external view returns (Fee.Data[3][] memory _fees) {
        _fees = new Fee.Data[3][](_vids.length);
        Fee.Data[3] memory _default = defaultEarnFees;
        for (uint i; i < _vids.length; i++) {
            uint vid = _vids[i];
            _fees[i] = _overrideDefaultEarnFees.get(vid) ? earnFees[vid] : _default;
            for (uint k; k < 3; k++) {
                if (_fees[i][k].receiver() == TX_ORIGIN)
                    _fees[i][k] = Fee.create(tx.origin, _fees[i][k].rate());
            }
        }
    }

    function getWithdrawFee(uint _vid) external view returns (address _receiver, uint16 _rate) {
        return _overrideDefaultWithdrawFee.get(_vid) ? withdrawFee[_vid].receiverAndRate() : defaultWithdrawFee.receiverAndRate();
    }

    function getWithdrawFees(uint[] calldata _vids) external view returns (Fee.Data[] memory _withdrawFees) {
        _withdrawFees = new Fee.Data[](_vids.length);
        Fee.Data _default = defaultWithdrawFee;
        for (uint i; i < _vids.length; i++) {
            uint vid = _vids[i];
            _withdrawFees[i] = _overrideDefaultWithdrawFee.get(vid) ? withdrawFee[vid] : _default;
        }
    }

    function setDefaultWithdrawFee(address withdrawReceiver, uint16 withdrawRate) external auth {
         _setDefaultWithdrawFee(withdrawReceiver, withdrawRate);
    }
    function _setDefaultWithdrawFee(address withdrawReceiver, uint16 withdrawRate) internal {
        defaultWithdrawFee = Fee.create(withdrawReceiver, withdrawRate);
        Fee.check(defaultWithdrawFee, 300);
        emit SetDefaultWithdrawFee(defaultWithdrawFee);
    }

    function setEarnFees(uint _vid, address[3] calldata earnReceivers, uint16[3] calldata earnRates) external auth {
        _overrideDefaultEarnFees.set(_vid);
        earnFees[_vid].set(earnReceivers, earnRates);
        Fee.check(earnFees[_vid], 3000);
        emit SetEarnFees(_vid, earnFees[_vid]);
    }
    function resetEarnFees(uint _vid) external auth {
        _overrideDefaultEarnFees.unset(_vid);
        delete earnFees[_vid];
        emit ResetEarnFees(_vid);
    }
    
    function setDefaultEarnFees(address[3] memory earnReceivers, uint16[3] memory earnRates) external auth {
        _setDefaultEarnFees(earnReceivers, earnRates);
    }
    function _setDefaultEarnFees(address[3] memory earnReceivers, uint16[3] memory earnRates) internal {
        defaultEarnFees.set(earnReceivers, earnRates);
        Fee.check(defaultEarnFees, 3000);
        emit SetDefaultEarnFees(defaultEarnFees);
    }

    function setWithdrawFee(uint _vid, address withdrawReceiver, uint16 withdrawRate) external auth {
        _overrideDefaultWithdrawFee.set(_vid);
        withdrawFee[_vid] = Fee.create(withdrawReceiver, withdrawRate);
        Fee.check(defaultWithdrawFee, 300);
        emit SetWithdrawFee(_vid, withdrawFee[_vid]);
    }

    function resetWithdrawFee(uint _vid) external auth {
        _overrideDefaultEarnFees.unset(_vid);
        withdrawFee[_vid] = Fee.Data.wrap(0);
         emit ResetWithdrawFee(_vid);
    }


}