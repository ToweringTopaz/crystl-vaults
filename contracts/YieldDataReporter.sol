// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IYieldDataRecorder {
    function receiveYieldData(YieldDataReporter.YieldData calldata _y) external;
}

abstract contract YieldDataReporter {
    
    struct YieldData {
        bool included;
        uint wantLockedBefore;
        uint sharesBefore;
        uint wantLockedAfter;
        uint sharesAfter;
    }    

}