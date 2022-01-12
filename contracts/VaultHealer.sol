// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerFactory.sol";
import "./QuartzUniV2ZapDeployer.sol";
import "./libs/IMagnetite.sol";
import "./VaultView.sol";

contract VaultHealer is VaultHealerFactory {
    
    bytes32 constant PATH_SETTER = keccak256("PATH_SETTER");

    IMagnetite immutable public magnetite;
    address immutable public zap;
    VaultView internal vaultView;

    event SetVaultView(VaultView);

    constructor(IMagnetite _magnetite, address _zapDeployer, VaultView _vaultView, Vault.Fees memory _fees, Vault.Fee memory _withdrawFee)
        VaultHealerBase(msg.sender) 
        VaultHealerBoostedPools(msg.sender)
        VaultHealerFees(msg.sender, _fees, _withdrawFee)
        VaultHealerPause(msg.sender)
    {
        magnetite = _magnetite;
        zap = QuartzUniV2ZapDeployer(_zapDeployer).deployZap();
        vaultView = _vaultView;
        _setupRole(PATH_SETTER, msg.sender);

    }
    
    function setVaultView(VaultView _vaultView) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vaultView = _vaultView;
        emit SetVaultView(_vaultView);
    }

    function setPath(address router, IERC20[] calldata path) external onlyRole(PATH_SETTER) {
        magnetite.overridePath(router, path);
    }

   function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return super.isApprovedForAll(account, operator) || operator == address(zap);
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
