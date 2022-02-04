// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./QuartzUniV2Zap.sol";
import "./VaultHealerGate.sol";
import "./VaultHealerBoostedPools.sol";
import "./Magnetite.sol";
import "./VaultView.sol";

contract VaultHealer is VaultHealerGate, VaultHealerBoostedPools {
    
    bytes32 constant PATH_SETTER = keccak256("PATH_SETTER");

    IMagnetite internal magnetite;
    QuartzUniV2Zap immutable zap;
    VaultView internal vaultView;

    event SetVaultView(VaultView);

    constructor(address withdrawReceiver, uint16 withdrawRate, address[3] memory earnReceivers, uint16[3] memory earnRates)
        VaultHealerBase(msg.sender) 
        VaultHealerBoostedPools(msg.sender)
    {
        magnetite = new Magnetite();
        zap = new QuartzUniV2Zap(address(this));
        vaultView = new VaultView(zap);
        vaultFeeManager = new VaultFeeManager(address(this), withdrawReceiver, withdrawRate, earnReceivers, earnRates);

    }
    
    function setVaultView(VaultView _vaultView) external onlyAdmin {
        vaultView = _vaultView;
        emit SetVaultView(_vaultView);
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
   }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155SupplyUpgradeable, VaultHealerGate, VaultHealerBoostedPools) {
        ERC1155SupplyUpgradeable._beforeTokenTransfer(operator, from, to, ids, amounts, data);        
        VaultHealerGate._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        VaultHealerBoostedPools._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        
    }

    //Passes calls to VaultView within a staticcall
    fallback(bytes calldata) external returns (bytes memory) {

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            //Safe transactions are from this address (will be staticcalls)
            let safe := eq(address(), caller())
            
            let result
            switch safe
            case 0 {
                //This does a staticcall to this address which is then delegated to VaultView. The static lock persists, preventing state changes
                result := staticcall(gas(), address(), 0, calldatasize(), 0, 0)
            }
            default {
                // Call VaultView
                // out and outsize are 0 because we don't know the size yet.
                result := delegatecall(gas(), sload(vaultView.slot), 0, calldatasize(), 0, 0)
            }

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
