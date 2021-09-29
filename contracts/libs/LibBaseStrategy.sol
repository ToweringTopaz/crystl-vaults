// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IPathStorage.sol";
import "./IUniRouter02.sol";
import "./StratStructs.sol";

library LibBaseStrategy {
    using SafeERC20 for IERC20;
    
    event SetAddresses(Addresses _addresses);
    event SetSettings(Settings _settings);

    function setAddresses(Addresses storage addresses, Addresses calldata _addresses)  external {
        for (uint i; i < addresses.earned.length; i++) {
            require(_addresses.earned[i] == addresses.earned[i], "cannot change earned address");
        }
        for (uint i; i < addresses.lpToken.length; i++) {
            require(_addresses.lpToken[i] == addresses.lpToken[i], "cannot change lpToken address");
        }        
        require(_addresses.want == addresses.want, "cannot change want address");
        require(_addresses.masterchef == addresses.masterchef, "cannot change masterchef address");
        require(_addresses.vaulthealer == addresses.vaulthealer, "cannot change masterchef address");
        
        _setAddresses(addresses, _addresses);
    }
    function _setAddresses(Addresses storage addresses, Addresses memory _addresses) public {
        require(_addresses.router != address(0), "Invalid router address");
        IUniRouter02(_addresses.router).factory(); // unirouter will have this function; bad address will revert
        require(_addresses.rewardFee != address(0), "Invalid reward address");
        require(_addresses.withdrawFee != address(0), "Invalid Withdraw address");
        require(_addresses.buybackFee != address(0), "Invalid buyback address");
        
        addresses.vaulthealer = _addresses.vaulthealer;
        addresses.router = _addresses.router;
        addresses.masterchef = _addresses.masterchef;
        addresses.rewardFee = _addresses.rewardFee;
        addresses.withdrawFee = _addresses.withdrawFee;
        addresses.buybackFee = _addresses.buybackFee;
        addresses.want = _addresses.want;
        addresses.earned = _addresses.earned;
        addresses.lpToken = _addresses.lpToken;
        
        emit SetAddresses(addresses);
    }
    function _setSettings(Settings storage settings, Settings memory _settings)  external {
        require(_settings.controllerFee + _settings.rewardRate + _settings.buybackRate <= FEE_MAX_TOTAL, "Max fee of 100%");
        require(_settings.withdrawFeeFactor >= WITHDRAW_FEE_FACTOR_LL, "_withdrawFeeFactor too low");
        require(_settings.withdrawFeeFactor <= WITHDRAW_FEE_FACTOR_MAX, "_withdrawFeeFactor too high");
        require(_settings.slippageFactor <= SLIPPAGE_FACTOR_UL, "_slippageFactor too high");
        
        settings.controllerFee = _settings.controllerFee;
        settings.rewardRate = _settings.rewardRate;
        settings.buybackRate = _settings.buybackRate;
        settings.withdrawFeeFactor = _settings.withdrawFeeFactor;
        settings.slippageFactor = _settings.slippageFactor;
        settings.tolerance = _settings.tolerance;
        settings.feeOnTransfer = _settings.feeOnTransfer;
        settings.dust = _settings.dust;
        settings.minBlocksBetweenSwaps = _settings.minBlocksBetweenSwaps;
        
        emit SetSettings(_settings);
    }
    function _safeSwap(Settings storage settings, Addresses storage addresses, uint256 _amountIn, address _tokenA, address _tokenB, address _to) public returns (uint256 burnedAmt) {
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            if (_tokenA == CRYSTL && _to == addresses.buybackFee)
                burnedAmt += _amountIn;
            IERC20(_tokenA).safeTransfer(_to, _amountIn);
            return burnedAmt;
        }
        address[] memory path = IPathStorage(address(this)).getPath(_tokenA, _tokenB);
        
        uint256[] memory amounts = IUniRouter02(addresses.router).getAmountsOut(_amountIn, path);
        uint256 amountOut = amounts[amounts.length - 1];

        if (_tokenB == CRYSTL && _to == addresses.buybackFee) {
            burnedAmt += amountOut;
        }
        amountOut = amountOut * settings.slippageFactor / 10000;
        if (settings.feeOnTransfer) {
            IUniRouter02(addresses.router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp + 600
            );
        } else {
            IUniRouter02(addresses.router).swapExactTokensForTokens(
                _amountIn,
                amountOut,
                path,
                _to,
                block.timestamp + 600
            );
        }
        return burnedAmt;
    }
    function distributeFees(Settings storage settings, Addresses storage addresses, address _earnedAddress, uint256 _earnedAmt, address _to) external returns (uint earnedAmt){
        earnedAmt = _earnedAmt;
        
        //gas optimization
        uint controllerFee = settings.controllerFee;
        uint rewardRate = settings.rewardRate;
        uint buybackRate = settings.buybackRate;
        
        // To pay for earn function
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt * controllerFee / FEE_MAX;
            _safeSwap(settings, addresses, fee, _earnedAddress, WNATIVE, _to);
            earnedAmt -= fee;
        }
        //distribute rewards
        if (rewardRate > 0) {
            uint256 fee = _earnedAmt * rewardRate / FEE_MAX;
            if (_earnedAddress == CRYSTL)
                IERC20(_earnedAddress).safeTransfer(addresses.rewardFee, fee);
            else
                _safeSwap(settings, addresses, fee, _earnedAddress, DAI, addresses.rewardFee);

            earnedAmt -= fee;
        }
        //burn crystl
        if (settings.buybackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * buybackRate / FEE_MAX;
            _safeSwap(settings, addresses, buyBackAmt, _earnedAddress, CRYSTL, addresses.buybackFee);
            earnedAmt -= buyBackAmt;
        }
        
        return earnedAmt;
    }
}