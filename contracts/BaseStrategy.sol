// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./libraries/StrategyConfig.sol";
import "./interfaces/IStrategy.sol";
import "hardhat/console.sol";
abstract contract BaseStrategy is IStrategy, ERC165 {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;


    uint constant FEE_MAX = 10000;
    StrategyConfig.MemPointer constant config = StrategyConfig.MemPointer.wrap(0x80);
    address public immutable vaultHealer;
    address public immutable implementation;

    constructor(address _vaultHealer) { 
        vaultHealer = _vaultHealer;
        implementation = address(this);
    }


    receive() external payable virtual { require(Address.isContract(msg.sender), "Strategy: invalid deposit"); }


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

    function initialize(bytes memory _config) external onlyVaultHealer {
        require(address(this) != implementation, "Strategy: This contract must be used by proxy");
        IERC20 _wantToken;
        assembly {
            _wantToken := and(0xffffffffffffffffffffffffffffffffffffffff, mload(add(_config, 116)))
            let len := mload(_config) //get length of config
            mstore(_config, 0x600c80380380823d39803df3fe) //simple bytecode which saves everything after the f3

            let configAddr := create(0, add(_config, 19), add(len,13)) //0 value; send 13 bytes plus _config
            if iszero(configAddr) { //create failed?
                revert(0, 0)
            }
        }
        
        _wantToken.safeIncreaseAllowance(msg.sender, type(uint256).max);
    }

    //should only happen when this contract deposits as a maximizer
    function onERC1155Received(
        address operator, address from, uint256 id, uint256, bytes calldata) external view onlyVaultHealer getConfig returns (bytes4) {
        require (operator == address(this) && from == address(0) && id == config.vid() >> 32, "Strategy: Improper ERC1155 deposit");
        return 0xf23a6e61;
    }

    //no batch transfer
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        revert("Strategy: Batch transfers not supported here");
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
        console.log("made it into distribute");
        earnedAmt = _earnedAmt;
        IUniRouter _router = config.router();

        uint feeTotalRate;
        for (uint i; i < 3; i++) {
            feeTotalRate += Fee.rate(fees[i]);
        }
        
        if (feeTotalRate > 0) {
            console.log("made it into conditional");
            uint256 feeEarnedAmt = _earnedAmt * feeTotalRate / FEE_MAX;
                        console.log("made it into conditional1");

            earnedAmt -= feeEarnedAmt;
                        console.log("made it into conditional2");

            uint nativeBefore = address(this).balance;
                        console.log("made it into conditional3");

            IWETH weth = _router.WETH();
                        console.log("made it into conditional4");

            safeSwap(feeEarnedAmt, _earnedToken, weth, address(this));
                        console.log("made it into conditional5");

            uint feeNativeAmt = address(this).balance - nativeBefore;
            console.log("made it down here");
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
        console.log("safeswap1");
        IUniRouter _router = config.router();
                console.log("safeswap2");

        IERC20[] memory path = config.magnetite().findAndSavePath(address(_router), _tokenA, _tokenB);
        console.log(address(path[0]));
        console.log(address(path[1]));
        console.log(address(path[2]));
        console.log(address(path[3]));


        //allow swap._router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(_router), _amountIn);
        console.log("safeswap4");

        if (config.feeOnTransfer()) {
                    console.log("safeswap5");

            _router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn, 
                _router.getAmountsOut(_amountIn, path)[path.length - 2] * config.slippageFactor() / 256,
                path,
                _to, 
                block.timestamp
            );
        } else {
                    console.log("safeswap6");

            _router.swapExactTokensForTokens(_amountIn, 0, path, _to, block.timestamp);                
        }
    }

    function configInfo() external view getConfig returns (
        uint256 vid,
        IERC20 want,
        uint256 wantDust,
        IERC20 rewardToken,
        address masterchef,
        uint pid, 
        IUniRouter _router, 
        IMagnetite _magnetite,
        IERC20[] memory earned,
        uint256[] memory earnedDust,
        uint slippageFactor,
        bool feeOnTransfer
    ) {
        vid = config.vid();
        (want, wantDust) = config.wantToken();
        rewardToken = config.targetWant();
        uint _tacticsA = Tactics.TacticsA.unwrap(config.tacticsA());
        masterchef = address(uint160(_tacticsA >> 96));
        pid = uint24(_tacticsA >> 64);
        _router = config.router();
        _magnetite = config.magnetite();
        uint len = config.earnedLength();
        earned = new IERC20[](len);
        earnedDust = new uint[](len);
        for (uint i; i < len; i++) {
            (earned[i], earnedDust[i]) = config.earned(i);
        }
        slippageFactor = config.slippageFactor();
        feeOnTransfer = config.feeOnTransfer();
    }


    function tactics() external view getConfig returns (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) {
        (tacticsA, tacticsB) = config.tactics();
    }

    function isMaximizer() external view getConfig returns (bool) {
        return config.isMaximizer();
    }

    //For IStrategy-conforming strategies who don't implement their own maximizers. Should revert if a strategy implementation
    //is incapable of being a maximizer.
    function getMaximizerImplementation() external virtual view returns (address) {
        return implementation;
    }

    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IStrategy).interfaceId;
    }
}