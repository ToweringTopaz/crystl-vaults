// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

library MoneyBomb {

    error MoneyBomb_TransferFailed(address recipient, uint amount);

    //Deploys a "money bomb" which transfers ether by immediately self-destructing
    function deploy(address payable recipient, uint amount) internal {
        address addr;
        assembly {
            mstore(21,0xff)
            mstore(20,recipient)
            mstore(0,0x73)
            addr := create(amount, 31, 22)
        }
        if (addr == address(0)) revert MoneyBomb_TransferFailed(recipient, amount);
    }

    //Standard method of transferring ether
    function unsafePay(address payable recipient, uint amount) internal {
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert MoneyBomb_TransferFailed(recipient, amount);
    }

    //Transfers using the standard method if the recipient is an EOA, contract in construction, etc.
    // i.e. something which cannot possibly perform a reentrancy exploit.
    // Pays contract addresses by deploying a money bomb instead
    function safePay(address payable recipient, uint amount) internal {
        function(address payable, uint) pay = recipient.code.length == 0 ? unsafePay : deploy;
        pay(recipient, amount);
    }
}