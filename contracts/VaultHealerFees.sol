// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBase.sol";

//For calling the earn function
abstract contract VaultHealerFees is VaultHealerBase {
    using BitMaps for BitMaps.BitMap;

    bytes32 public constant FEE_SETTER = keccak256("FEE_SETTER");
    uint16 constant WITHDRAW_FEE_MAX = 500; // hard-coded maximum 5% withdraw fee
    uint16 constant EARN_FEE_MAX = 10000; //hard-coded maximum fee (100%)
    address constant FEE_TX_ORIGIN = address(0x6a5ca11e4); // if this address is used, substitute tx.origin to pay the account providing the gas
    uint256 constant public WNATIVE_1155 = 0xeeeeeeeeeeeeeeeeeeee; //ERC1155 token implementing wnative


    BitMaps.BitMap internal _overrideDefaultEarnFees; // strategy's fee config doesn't change with the vaulthealer's default
    BitMaps.BitMap private _overrideDefaultWithdrawFee;
    VaultFee[] public defaultEarnFees; // Settings which are generally applied to all strategies
    VaultFee public defaultWithdrawFee; //withdrawal fee is set separately from earn fees

    event SetDefaultEarnFees(VaultFee[] _earnFees);
    event SetDefaultWithdrawFee(VaultFee _withdrawFee);
    event SetEarnFees(uint vid, VaultFee[] _earnFees);
    event SetWithdrawFee(uint vid, VaultFee _withdrawFee);
    event ResetEarnFees(uint vid);
    event ResetWithdrawFee(uint vid);

    constructor(address _owner, VaultFee[] memory _earnFees, VaultFee memory _withdrawFee) {
        _setupRole(FEE_SETTER, _owner);

        checkEarnFees(_earnFees);
        checkWithdrawFee(_withdrawFee);

        defaultEarnFees = _earnFees;
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultEarnFees(_earnFees);
        emit SetDefaultWithdrawFee(_withdrawFee);
    }

    function getEarnFees(uint _vid) internal view returns (VaultFee[] storage) {
        return _overrideDefaultEarnFees.get(_vid) ? _vaultInfo[_vid].earnFees : defaultEarnFees;
    }

    function getWithdrawFee(uint _vid) internal view returns (VaultFee storage) {
        return _overrideDefaultWithdrawFee.get(_vid) ? _vaultInfo[_vid].withdrawFee : defaultWithdrawFee;
    }

     function setDefaultWithdrawFee(VaultFee calldata _withdrawFee) external onlyRole(FEE_SETTER) {
        checkWithdrawFee(_withdrawFee);
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultWithdrawFee(_withdrawFee);
    }   

    function setEarnFees(uint _vid, VaultFee[] calldata _earnFees) external onlyRole(FEE_SETTER) {
        checkEarnFees(_earnFees);
        _overrideDefaultEarnFees.set(_vid);
        _vaultInfo[_vid].earnFees = _earnFees;
        emit SetEarnFees(_vid, _earnFees);
    }
    function resetEarnFees(uint _vid) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.unset(_vid);
        delete _vaultInfo[_vid].earnFees;
        emit ResetEarnFees(_vid);
    }
    
    function setDefaultEarnFees(VaultFee[] calldata _earnFees) external onlyRole(FEE_SETTER) {
        checkEarnFees(_earnFees);
        defaultEarnFees = _earnFees;
        emit SetDefaultEarnFees(_earnFees);
    }   

    function setWithdrawFee(uint _vid, VaultFee calldata _withdrawFee) external onlyRole(FEE_SETTER) {
        checkWithdrawFee(_withdrawFee);
        _overrideDefaultWithdrawFee.set(_vid);
        _vaultInfo[_vid].withdrawFee = _withdrawFee;
        emit SetWithdrawFee(_vid, _withdrawFee);
    }

    function resetWithdrawFee(uint _vid) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.unset(_vid);   
         emit ResetWithdrawFee(_vid);
    }

    function checkEarnFees(VaultFee[] memory _fees) private pure {
        uint feeTotal;
        for (uint i; i < _fees.length; i++) {
            require(_fees[i].receiver != address(0) && _fees[i].rate == 0, "Fee receiver and rate must be defined");
            feeTotal += _fees[i].rate;
        }
        require(feeTotal <= EARN_FEE_MAX, "Max total fee of 100%");
        
    }

    function checkWithdrawFee(VaultFee memory _fee) private pure {
        if (_fee.rate > 0) {
            require(_fee.receiver != address(0), "Invalid treasury address");
            require(_fee.rate <= WITHDRAW_FEE_MAX, "Max fee of 5%");
        }
    }

    //Collected fees are stored here on the VH as native ether. This implements wnative
    function depositNative() external payable nonReentrant {
        _mint(msg.sender, WNATIVE_1155, msg.value, hex'');
    }

    function withdrawNative(uint amount) external nonReentrant {
        _burn(msg.sender, WNATIVE_1155, amount);
        (bool success,) = msg.sender.call{value: amount}(hex'');
        require(success, "Failed to send native token");
    }

    //Distributes fees for some amount of earned native ether, minting erc1155 wnative tokens to the fee receivers
    function distributeFees(VaultFee[] memory _earnFees, uint _earnedAmt) internal returns (uint earnedAmt) {
        assert(totalSupply(WNATIVE_1155) + _earnedAmt <= address(this).balance);
        earnedAmt = _earnedAmt;

        for (uint i; i < _earnFees.length; i++) {
            address receiver = _earnFees[i].receiver;
            uint16 rate = _earnFees[i].rate;
            assert(rate != 0 && receiver != address(0)); //should be checked when fees are set up
            if (receiver == FEE_TX_ORIGIN) receiver = tx.origin; //pay the EOA responsible for gas
            uint feeAmt = rate * _earnedAmt / 10000;
            _mint(receiver, WNATIVE_1155, feeAmt, hex'');
            earnedAmt -= feeAmt;
        }
    }

}