// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract GasGuard is Ownable {
    
    bool private _enabled;
    event GasIncrease(bytes4 indexed sig, uint256 oldValue, uint256 newValue);
    event ResetGas(bytes4 indexed sig);
    mapping(bytes4 => uint) public _gasNeeded;
    
    function setGasGuard(bool _status) external virtual onlyOwner {
        _enabled = _status;
    }
    
    function resetGas(bytes4 _sig) external virtual onlyOwner {
        _gasNeeded[_sig] = 0;
        emit ResetGas(_sig);
    }
    
    function gasGuardEnabled() public view virtual returns (bool) {
        return _enabled;
    }
    
    //This modifier will ensure that Metamask demands the correct amount of gas for an EXTERNAL function.
    //Must only be invoked once per call as it maps to the calldata's function signature. Create separate
    //external and _internal functions if needed.
    modifier gasGuzzler() {
        require(!gasGuardEnabled() || gasleft() >= _gasNeeded[msg.sig], "GasGuard: Insufficient gas");
        uint gasStart;
        
        _;
        
        if (gasGuardEnabled()) {
            uint gasUsed = gasStart - gasleft();
            if (gasUsed > _gasNeeded[msg.sig] && gasUsed < block.gaslimit * 8 / 10) {
                uint oldGasNeeded = _gasNeeded[msg.sig]; 
                _gasNeeded[msg.sig] = gasUsed + 50000;
                emit GasIncrease(msg.sig, oldGasNeeded, _gasNeeded[msg.sig]);
            }
        }
    }
    
}