/*
{
	"functionDebugData": {},
	"generatedSources": [],
	"linkReferences": {},
	"object": "60868061000e600039806000f3fe36600081818237737979797979797979797979797979797979797979331415603757633074440c813560e01c141560335733ff5b8091505b303314156042578091505b8082801560565782833685305afa91506074565b8283368573bebebebebebebebebebebebebebebebebebebebe5af491505b503d82833e806081573d82fd5b503d81f3",
	"opcodes": "PUSH1 0x86 DUP1 PUSH2 0xE PUSH1 0x0 CODECOPY DUP1 PUSH1 0x0 RETURN INVALID CALLDATASIZE PUSH1 0x0 DUP2 DUP2 DUP3 CALLDATACOPY PUSH20 0x7979797979797979797979797979797979797979 CALLER EQ ISZERO PUSH1 0x37 JUMPI PUSH4 0x3074440C DUP2 CALLDATALOAD PUSH1 0xE0 SHR EQ ISZERO PUSH1 0x33 JUMPI CALLER SELFDESTRUCT JUMPDEST DUP1 SWAP2 POP JUMPDEST ADDRESS CALLER EQ ISZERO PUSH1 0x42 JUMPI DUP1 SWAP2 POP JUMPDEST DUP1 DUP3 DUP1 ISZERO PUSH1 0x56 JUMPI DUP3 DUP4 CALLDATASIZE DUP6 ADDRESS GAS STATICCALL SWAP2 POP PUSH1 0x74 JUMP JUMPDEST DUP3 DUP4 CALLDATASIZE DUP6 PUSH20 0xBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBEBE GAS DELEGATECALL SWAP2 POP JUMPDEST POP RETURNDATASIZE DUP3 DUP4 RETURNDATACOPY DUP1 PUSH1 0x81 JUMPI RETURNDATASIZE DUP3 REVERT JUMPDEST POP RETURNDATASIZE DUP2 RETURN ",
	"sourceMap": "155:2314::-:0;;;;;;;"
}



*/
/*
/// @use-src 0:"VHStrategyProxy_flat.sol"
object "VHStrategyProxy" {
    code {
        /// @src 0:155:2469  "contract VHStrategyProxy {..."
        codecopy(0, dataoffset("VHStrategyProxy_deployed"), datasize("VHStrategyProxy_deployed"))
        return(0, datasize("VHStrategyProxy_deployed"))
    }
    /// @use-src 0:"VHStrategyProxy_flat.sol"
    object "VHStrategyProxy_deployed" {
        code {
            /// @src 0:155:2469  "contract VHStrategyProxy {..."
            let untrusted := calldatasize() //trust transactions with zero calldata or from vaulthealer or this address
            calldatacopy(0, 0, calldatasize())
            if eq(caller(), 0x7979797979797979797979797979797979797979) {
                let selector := shr(224, calldataload(0))
                if eq(selector, 0x3074440c) { //_destroy_
                    selfdestruct(caller())
                }
                untrusted := 0 
            }
            if eq(caller(), address()) {
                untrusted := 0
            }
            let result
            switch untrusted
            case 0 {
                result := delegatecall(gas(), 0xbebebebebebebebebebebebebebebebebebebebe, 0, calldatasize(), 0, 0)
            } default {
                result := staticcall(gas(), address(), 0, calldatasize(), 0, 0)
            }
            returndatacopy(0, 0, returndatasize())
            if iszero(result) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
        //data ".metadata" hex""
    }
}
*/
/// @use-src 0:"VHStrategyProxy_flat.sol"
object "VHStrategyProxy" {
    code {
            let _0 := callvalue()
            mstore(_0, 0xad3b358e) //getProxyData()
            pop(staticcall(gas(), caller(), _0, 4, 0x5c, 20))

            mstore(_0, or(shl(192,0x3660008181823773), shl(32, caller())))
            datacopy(0x1c, dataoffset("bytecodeSegment2"), 0x40)
            datacopy(0x70, dataoffset("bytecodeSegment3"), 0x16)
            let dataLength := sub(returndatasize(),20)
            returndatacopy(0x86, 20, dataLength)

            return(_0, add(dataLength,0x86))
    }
    data "bytecodeSegment2" hex"331415603757633074440c813560e01c141560335733ff5b8091505b303314156042578091505b8082801560565782833685305afa91506074565b8283368573"
    data "bytecodeSegment3" hex"5af491505b503d82833e806081573d82fd5b503d81f3"
}