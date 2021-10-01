// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BaseStrategyIndependent.sol";
import "./BaseStrategyMaxiCore.sol";

abstract contract BaseStrategyMaxiSupplier is BaseStrategyIndependent {
    
    //Maximizer-incapable strategies throw
    //Maximizer suppliers return address(0)
    //Maximizer cores return their want address
    function maximizerInfo() external pure override returns (address maxiToken) {
        return address(0);
    }

    ExportInfo[MAX_EXPORTS] public exportInfo;
    uint totalXShares;
    uint exportLength;
    
    function _settleUser(address _user, uint _exportID) internal {
        ExportInfo storage export = exportInfo[_exportID];
        //UserExport storage user = export.user;
        
        //uint shareDebt = export.shareDebt[_user];
        //uint sharesToTransfer = (userShares * export.SharesEarned / export.sharesEarned) - shareDebt;
        //export.shareDebt[_user] = shareDebt + sharesToTransfer;
        
        //BaseStrategyMaxiCore(core.strat).transferShares(_user, sharesToTransfer);
    }
}