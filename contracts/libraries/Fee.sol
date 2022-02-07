// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.9;

library Fee {
    using Fee for Data;

    type Data is uint256;

    uint256 constant FEE_MAX = 3000; // 100 = 1% : basis points

    function rate(Data _fee) internal pure returns (uint16) {
        return uint16(Data.unwrap(_fee));
    }
    function receiver(Data _fee) internal pure returns (address) {
        return address(uint160(Data.unwrap(_fee) >> 16));
    }
    function receiverAndRate(Data _fee) internal pure returns (address, uint16) {
        uint fee = Data.unwrap(_fee);
        return (address(uint160(fee >> 16)), uint16(fee));
    }
    function create(address _receiver, uint16 _rate) internal pure returns (Data) {
        return Data.wrap((uint256(uint160(_receiver)) << 16) | _rate);
    }

    function set(Data[3] storage _fees, address[3] memory _receivers, uint16[3] memory _rates) internal {

        uint feeTotal;
        for (uint i; i < 3; i++) {
            address _receiver = _receivers[i];
            uint16 _rate = _rates[i];
            require(_receiver != address(0) || _rate == 0, "Invalid treasury address");
            feeTotal += _rate;
            uint256 _fee = uint256(uint160(_receiver)) << 16 | _rate;
            _fees[i] = Data.wrap(_fee);
        }
        require(feeTotal <= FEE_MAX, "Max total fee of 30%");
    }
    function check(Data[3] memory _fees) internal pure { 
        uint totalRate;
        for (uint i; i < 3; i++) {
            (address _receiver, uint _rate) = _fees[i].receiverAndRate();
            require(_receiver != address(0) || _rate == 0, "Invalid treasury address");
            totalRate += _rate;
        }
        require(totalRate <= FEE_MAX, "Max total fee of 30%");
    }

    function check(Data _fee) internal pure { 
        (address _receiver, uint _rate) = _fee.receiverAndRate();
        if (_rate > 0) {
            require(_receiver != address(0), "Invalid treasury address");
            require(_rate <= FEE_MAX, "Max fee of 30%");
        }
    }

}