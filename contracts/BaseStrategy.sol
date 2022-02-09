// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./libraries/StrategyStandard.sol";
import "./interfaces/IStrategy.sol";

abstract contract BaseStrategy is Initializable, IStrategy {
    using SafeERC20 for IERC20;
    using StrategyStandard for StrategyStandard.MemPointer;


    uint constant FEE_MAX = 10000;
    StrategyStandard.MemPointer constant config = StrategyStandard.MemPointer.wrap(0x80);
    address public immutable vaultHealer;


    constructor(address _vaultHealer) { 
        vaultHealer = _vaultHealer; 
    }


    receive() external payable virtual {}


    modifier onlyVaultHealer {
        _requireVaultHealer();
        _;
    }
    function _requireVaultHealer() private view {
        require(msg.sender == vaultHealer, "Strategy: Function can only be called by VaultHealer");
    }


    modifier getConfig() {
        _getConfig();
        _;
    }
    function _getConfig() private view {
        address configAddr = configAddress();
        assembly {
            if gt(mload(0x40), 0x80) { // asserting that this function is only called once at the beginning of every incoming call
                revert(0,0)
            }
            let len := sub(extcodesize(configAddr), 1) //get length, subtracting 1 for the invalid opcode
            mstore(0x40, add(0x80, len)) //update free memory pointer
            extcodecopy(configAddr, 0x80, 1, len) //get the data
        }
    }


    function initialize(bytes calldata _config) external initializer onlyVaultHealer {
        address targetAddr = configAddress();
        
        assembly {
            let len := _config.length //deploy with 13-byte code below plus config data
            mstore(0x00, 0x600c80380380823d39803df3fe00000000000000000000000000000000000000) //simple bytecode which saves everything after the f3
            calldatacopy(13, _config.offset, _config.length) //place everything aftr the f3
            let configAddr := create(0, 0, add(len,13)) //0 value; send 13 bytes plus _config
            if not(eq(targetAddr, configAddr)) { //create failed?
                revert(0, 0)
            }
        }
        IERC20 _wantToken = IERC20(address(bytes20(_config[52:72])));
        _wantToken.safeIncreaseAllowance(msg.sender, type(uint256).max);
    }

    function panic() external getConfig onlyVaultHealer {
        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        Tactics.emergencyVaultWithdraw(tacticsA, tacticsB);
    }
    function unpanic() external getConfig onlyVaultHealer { 
        _farm();
    }


    function router() external view getConfig returns (IUniRouter _router) {
        return config.router();
    }


    function wantToken() external view getConfig returns (IERC20 _token) {
        (_token,) = config.wantToken();
    }


    function configAddress() public view returns (address configAddr) {
        assembly {
            mstore(0, or(0xd694000000000000000000000000000000000000000001000000000000000000, shl(80,address())))
            configAddr := and(0xffffffffffffffffffffffffffffffffffffffff, keccak256(0, 23)) //create address, nonce 1
        }
    }


    function vaultSharesTotal() external view getConfig returns (uint256) {
        return _vaultSharesTotal();
    }
    function _vaultSharesTotal() internal view virtual returns (uint256) {
        return Tactics.vaultSharesTotal(config.tacticsA());
    }


    function wantLockedTotal() external view getConfig returns (uint256) {
        return _wantLockedTotal();
    }
    function _wantLockedTotal() internal view virtual returns (uint256) {
        (IERC20 _wantToken, ) = config.wantToken();
        return _wantToken.balanceOf(address(this)) + _vaultSharesTotal();
    }


    function _vaultDeposit(uint256 _amount) internal virtual {   
        //token allowance for the pool to pull the correct amount of funds only
        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        (IERC20 _wantToken,) = config.wantToken();
        _wantToken.safeIncreaseAllowance(address(uint160(Tactics.TacticsA.unwrap(tacticsA) >> 96)), _amount); //address(tacticsA >> 96) is masterchef        
        Tactics.deposit(tacticsA, tacticsB, _amount);
    }


    //Safely deposits want tokens in farm
    function _farm() internal virtual {
        (IERC20 _wantToken, uint dust) = config.wantToken();
        uint256 wantAmt = _wantToken.balanceOf(address(this));
        if (wantAmt == 0) return;
        
        uint256 sharesBefore = _vaultSharesTotal();
        
        _vaultDeposit(wantAmt); //approves the transfer then calls the pool contract to deposit
        uint256 sharesAfter = _vaultSharesTotal();
        
        //including dust to reduce the chance of false positives
        //safety check, will fail if there's a deposit fee rugpull or serious bug taking deposits
        require(sharesAfter + _wantToken.balanceOf(address(this)) + dust >= (sharesBefore + wantAmt) * config.slippageFactor() / 10000,
            "High vault deposit slippage");
        return;
    }

    function distribute(Fee.Data[3] calldata fees, IERC20 _earnedToken, uint256 _earnedAmt) internal returns (uint earnedAmt) {

        earnedAmt = _earnedAmt;
        IUniRouter _router = config.router();

        uint feeTotalRate;
        for (uint i; i < 3; i++) {
            feeTotalRate += Fee.rate(fees[i]);
        }
        
        if (feeTotalRate > 0) {
            uint256 feeEarnedAmt = _earnedAmt * feeTotalRate / FEE_MAX;
            earnedAmt -= feeEarnedAmt;
            uint nativeBefore = address(this).balance;
            IWETH weth = _router.WETH();
            safeSwap(feeEarnedAmt, _earnedToken, weth, address(this));
            uint feeNativeAmt = address(this).balance - nativeBefore;

            weth.withdraw(weth.balanceOf(address(this)));
            for (uint i; i < 3; i++) {
                (address receiver, uint rate) = Fee.receiverAndRate(fees[i]);
                if (receiver == address(0) || rate == 0) break;
                (bool success,) = receiver.call{value: feeNativeAmt * rate / feeTotalRate, gas: 0x40000}("");
                require(success, "Strategy: Transfer failed");
            }
        }
    }

    function safeSwap(
        uint256 _amountIn,
        IERC20 _tokenA,
        IERC20 _tokenB,
        address _to
    ) internal {
        //Handle one-token paths which are simply a transfer
        if (_tokenA == _tokenB) {
            if (_to != address(this)) //skip transfers to self
                _tokenA.safeTransfer(_to, _amountIn);
            return;
        }
        IUniRouter _router = config.router();
        IERC20[] memory path = config.magnetite().findAndSavePath(address(_router), _tokenA, _tokenB);

        /////////////////////////////////////////////////////////////////////////////////////////////
        //this code snippet below could be removed if findAndSavePath returned a right-sized array //
        uint256 counter=0;
        for (counter; counter<path.length; counter++){
            if (address(path[counter]) == address(0)) break;
        }
        IERC20[] memory cleanedUpPath = new IERC20[](counter);
        for (uint256 i=0; i<counter; i++) {
            cleanedUpPath[i] =path[i];
        }
        //this code snippet above could be removed if findAndSavePath returned a right-sized array

        //allow swap._router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(_router), _amountIn);

        if (config.feeOnTransfer()) {
            _router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn, 
                _router.getAmountsOut(_amountIn, cleanedUpPath)[cleanedUpPath.length - 2] * config.slippageFactor() / 10000,
                cleanedUpPath,
                _to, 
                block.timestamp
            );
        } else {
            _router.swapExactTokensForTokens(_amountIn, 0, cleanedUpPath, _to, block.timestamp);                
        }
    }

    function isMaximizer() external view getConfig returns (bool) {
        return config.isMaximizer();
    }

    function maximizerRewardToken() external view getConfig returns (IERC20) {
        return config.targetWant();
    }

    function getMaximizerImplementation() external view returns (IStrategy) {
        return IStrategy(address(this));
    }
}