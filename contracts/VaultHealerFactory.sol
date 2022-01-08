// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./VaultHealerBoostedPools.sol";
import "./VHStrategyProxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

abstract contract VaultHealerFactory is VaultHealerBoostedPools {

    //bytes constant proxyCode = VHStrategyProxy.deployedcode;

    event StrategyCreated(address indexed _implementation, address indexed _instance);

    address proxyImplementation;
    bytes proxyMetadata;

//    "60868061000e600039806000f3fe3660008181823773"
//    7979797979797979797979797979797979797979"331415603757633074440c813560e01c141560335733ff5b8091505b303314156042578091505b8082801560565782833685305afa91506074565b8283368573bebebebebebebebebebebebebebebebebebebebe5af491505b503d82833e806081573d82fd5b503d81f3"

    function getProxyData() external returns (address _implementation, bytes memory _metadata) {
        _implementation = proxyImplementation;
        _metadata = proxyMetadata;
        delete proxyImplementation;
        delete proxyMetadata;
    }

    function createVault(
        address _implementation,
        IERC20 _wantToken,
        address _masterchefAddress,
        address _tacticAddress,
        uint256 _pid,
        VaultSettings calldata _settings,
        IERC20[] calldata _earned,
        address _targetVault //maximizer target
    ) external onlyRole("VAULT_ADDER") {
        proxyImplementation = _implementation;
        address newStrat = Create2.deploy(0, bytes32(_vaultInfo.length), type(VHStrategyProxy).creationCode);
        IStrategy(newStrat).initialize(_wantToken, _masterchefAddress, _tacticAddress, _pid, _settings, _earned, _targetVault);
        addVault(newStrat, _settings.minBlocksBetweenEarns);
    }
    
}