// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./VaultHealerBase.sol";

//For calling the earn function
abstract contract VaultHealerFees is VaultHealerBase {
    using BitMaps for BitMaps.BitMap;
    using Vault for Vault.Fee[];
    using Vault for Vault.Fee;

    bytes32 public constant FEE_SETTER = keccak256("FEE_SETTER");
    uint16 constant WITHDRAW_FEE_MAX = 500; // hard-coded maximum 5% withdraw fee
    uint16 constant EARN_FEE_MAX = 10000; //hard-coded maximum fee (100%)
    address constant public TX_ORIGIN = address(bytes20(keccak256("TX_ORIGIN"))); // if this address is used, substitute tx.origin to pay the account providing the gas
    uint256 constant public WNATIVE_1155 = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee; //ERC1155 token implementing wnative

    BitMaps.BitMap internal _overrideDefaultEarnFees; // strategy's fee config doesn't change with the vaulthealer's default
    BitMaps.BitMap private _overrideDefaultWithdrawFee;
    Vault.Fee[] public defaultEarnFees; // Settings which are generally applied to all strategies
    Vault.Fee public defaultWithdrawFee; //withdrawal fee is set separately from earn fees

    event SetDefaultEarnFees(Vault.Fee[] _earnFees);
    event SetDefaultWithdrawFee(Vault.Fee _withdrawFee);
    event SetEarnFees(uint vid, Vault.Fee[] _earnFees);
    event SetWithdrawFee(uint vid, Vault.Fee _withdrawFee);
    event ResetEarnFees(uint vid);
    event ResetWithdrawFee(uint vid);

    constructor(address _owner, address[] memory _earnFeeReceivers, uint16[] memory _earnFeeRates, address _withdrawFeeReceiver, uint16 _withdrawFeeRate) {
        _setupRole(FEE_SETTER, _owner);

        Vault.Fee _withdrawFee = Vault.createFee(_withdrawFeeReceiver, _withdrawFeeRate);
        checkWithdrawFee(_withdrawFee);

        defaultEarnFees.set(_earnFeeReceivers, _earnFeeRates);

        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultEarnFees(defaultEarnFees);
        emit SetDefaultWithdrawFee(_withdrawFee);
    }

    function getEarnFees(uint _vid) internal view returns (Vault.Fee[] storage) {
        return _overrideDefaultEarnFees.get(_vid) ? _vaultInfo[_vid].earnFees : defaultEarnFees;
    }
    function getWithdrawFee(uint _vid) internal view returns (address receiver, uint rate) {
        return _overrideDefaultWithdrawFee.get(_vid) ? 
            _vaultInfo[_vid].withdrawFee.receiverAndRate() : 
            defaultWithdrawFee.receiverAndRate();
    }

    function setDefaultWithdrawFee(Vault.Fee _withdrawFee) external onlyRole(FEE_SETTER) {
        checkWithdrawFee(_withdrawFee);
        defaultWithdrawFee = _withdrawFee;
        emit SetDefaultWithdrawFee(_withdrawFee);
    }   

    function setEarnFees(uint _vid, address[] calldata _earnFeeReceivers, uint16[] calldata _earnFeeRates) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.set(_vid);
        _vaultInfo[_vid].earnFees.set(_earnFeeReceivers, _earnFeeRates);
        emit SetEarnFees(_vid, _vaultInfo[_vid].earnFees);
    }

    function resetEarnFees(uint _vid) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.unset(_vid);
        delete _vaultInfo[_vid].earnFees;
        emit ResetEarnFees(_vid);
    }
    function setDefaultEarnFees(address[] calldata _earnFeeReceivers, uint16[] calldata _earnFeeRates) external onlyRole(FEE_SETTER) {
        defaultEarnFees.set(_earnFeeReceivers, _earnFeeRates);
        emit SetDefaultEarnFees(defaultEarnFees);
    }

    function setWithdrawFee(uint _vid, address _withdrawFeeReceiver, uint16 _withdrawFeeRate) external onlyRole(FEE_SETTER) {
        _overrideDefaultWithdrawFee.set(_vid);
        _vaultInfo[_vid].withdrawFee = Vault.createFee(_withdrawFeeReceiver, _withdrawFeeRate);
        emit SetWithdrawFee(_vid, _vaultInfo[_vid].withdrawFee);
    }

    function resetWithdrawFee(uint _vid) external onlyRole(FEE_SETTER) {
        _overrideDefaultEarnFees.unset(_vid);   
         emit ResetWithdrawFee(_vid);
    }

    function checkWithdrawFee(Vault.Fee _fee) private pure {
        if (_fee.rate() > 0) {
            require(_fee.receiver() != address(0), "Invalid treasury address");
            require(_fee.rate() <= WITHDRAW_FEE_MAX, "Max fee of 5%");
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
    function totalRate(Vault.Fee[] memory _earnFees) internal pure returns (uint total) {
        for (uint i; i < _earnFees.length; i++) {
            total += _earnFees[i].rate();
        }
        return total;
    }

    //Distributes fees for some amount of earned native ether, minting erc1155 wnative tokens to the fee receivers
    function distributeFees(Vault.Fee[] memory _earnFees, uint feeRateTotal) internal {
        uint feeAmtTotal = address(this).balance - totalSupply(WNATIVE_1155);

        for (uint i; i < _earnFees.length; i++) {
            (address receiver, uint16 rate) = _earnFees[i].receiverAndRate();
            assert(rate != 0 && receiver != address(0)); //should be checked when fees are set up
            if (receiver == TX_ORIGIN) receiver = tx.origin; //pay the EOA responsible for gas

            uint feeAmt = rate * feeAmtTotal / feeRateTotal;
            _mint(receiver, WNATIVE_1155, feeAmt, hex'');
        }
    }

    receive() external payable {
        require(Address.isContract(msg.sender));
    }
}