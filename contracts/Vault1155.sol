// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";


contract Vault1155 is ERC1155 {

    address immutable public vaultHealer;

    constructor(address _vaultHealer) ERC1155("") {
        vaultHealer = _vaultHealer;
    }

    function mint


}