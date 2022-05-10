// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./libraries/StrategyConfig.sol";
import "./interfaces/IStrategy.sol";

abstract contract BaseStrategy is IStrategy, ERC165 {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;

    uint constant FEE_MAX = 10000;
    uint16 constant CONFIG_POINTER = 0x200;
    StrategyConfig.MemPointer constant config = StrategyConfig.MemPointer.wrap(CONFIG_POINTER);
    IVaultHealer public immutable vaultHealer;
    IStrategy public immutable implementation;

    constructor(IVaultHealer _vaultHealer) { 
        vaultHealer = _vaultHealer;
        implementation = this;
    }


    receive() external payable virtual { if (!Address.isContract(msg.sender)) revert Strategy_ImproperEthDeposit(msg.sender, msg.value); }

    modifier onlyVaultHealer {
        _requireVaultHealer();
        _;
    }
    function _requireVaultHealer() private view {
        if (msg.sender != address(vaultHealer)) revert Strategy_NotVaultHealer(msg.sender);
    }

    modifier getConfig() {
        if (implementation == this) revert Muppet(msg.sender);
        uint ptr = _getConfig();
        if (ptr != CONFIG_POINTER) revert Strategy_CriticalMemoryError(ptr);
        _;
    }

    function _getConfig() private view returns (uint ptr) {
        address configAddr = configAddress();
        assembly ("memory-safe") {
            let len := sub(extcodesize(configAddr), 1) //get length, subtracting 1 for the invalid opcode
            ptr := mload(0x40)
            if lt(ptr, CONFIG_POINTER) { ptr := CONFIG_POINTER }
            mstore(0x40, add(ptr, len)) //update free memory pointer
            extcodecopy(configAddr, ptr, 1, len) //get the data
        }
    }

    function initialize(bytes memory _config) public virtual onlyVaultHealer {
        if (this == implementation) revert Strategy_InitializeOnlyByProxy();
        assembly ("memory-safe") {
            let len := mload(_config) //get length of config
            mstore(_config, 0x600c80380380823d39803df3fe) //simple bytecode which saves everything after the f3

            let configAddr := create(0, add(_config, 19), add(len,13)) //0 value; send 13 bytes plus _config
            if iszero(configAddr) { //create failed?
                revert(0, 0)
            }
        }
		StrategyConfig.MemPointer config_ = StrategyConfig.MemPointer.wrap(_getConfig());
		(IERC20 _wantToken,) = config_.wantToken();
		_wantToken.safeIncreaseAllowance(msg.sender, type(uint256).max);

    }

    //should only happen when this contract deposits as a maximizer
    function onERC1155Received(
        address operator, address from, uint256 id, uint256, bytes calldata) external view onlyVaultHealer getConfig returns (bytes4) {
        if (operator != address(this) || from != address(0) || id != config.vid() >> 16) revert Strategy_Improper1155Deposit(operator, from, id);
        return 0xf23a6e61;
    }

    //no batch transfer
    function onERC1155BatchReceived(address operator, address from, uint256[] calldata ids, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        revert Strategy_Improper1155BatchDeposit(operator, from, ids);
    }

    function panic() external getConfig onlyVaultHealer {
        _vaultEmergencyWithdraw();
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
        assembly ("memory-safe") {
            mstore(0, or(0xd694000000000000000000000000000000000000000001000000000000000000, shl(80,address())))
            configAddr := and(0xffffffffffffffffffffffffffffffffffffffff, keccak256(0, 23)) //create address, nonce 1
        }
    }

    function wantLockedTotal() external view getConfig returns (uint256) {
        return _wantLockedTotal();
    }
    function _wantLockedTotal() internal view virtual returns (uint256) {
        (IERC20 _wantToken, ) = config.wantToken();
        return _wantToken.balanceOf(address(this)) + _vaultSharesTotal();
    }


    //Safely deposits want tokens in farm
    function _farm() internal virtual {
        (IERC20 _wantToken, uint dust) = config.wantToken();
        uint256 wantAmt = _wantToken.balanceOf(address(this));
        if (wantAmt == 0) return;
        
        uint256 sharesBefore = _vaultSharesTotal();
        _vaultDeposit(_wantToken, wantAmt); //approves the transfer then calls the pool contract to deposit
        uint256 sharesAfter = _vaultSharesTotal();
        
        //including dust to reduce the chance of false positives
        //safety check, will fail if there's a deposit fee rugpull or serious bug taking deposits
        if (sharesAfter + _wantToken.balanceOf(address(this)) + dust < (sharesBefore + wantAmt) * config.slippageFactor() / 256)
            revert Strategy_ExcessiveFarmSlippage();
        return;
    }

    function safeSwap(
        uint256 _amountIn,
        IERC20 _tokenA,
        IERC20 _tokenB
    ) internal {
        if (_tokenA == _tokenB) return; //Do nothing for one-token paths
        IERC20[] memory path = config.magnetite().findAndSavePath(address(config.router()), _tokenA, _tokenB);
        require(path[0] == _tokenA && path[path.length - 1] == _tokenB, "Strategy: received invalid path for swap");
        safeSwap(_amountIn, path);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(IERC20 tokenA, IERC20 tokenB) internal pure returns (IERC20 token0, IERC20 token1) {
        if (tokenA == tokenB) revert IdenticalAddresses(tokenA, tokenB);
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (address(token0) == address(0)) revert ZeroAddress();
    }

    function safeSwap(
        uint256 _amountIn,
        IERC20[] memory path
    ) internal {
        IUniRouter _router = config.router();
        IUniFactory factory = _router.factory();

        uint amountOutMin = config.feeOnTransfer() ? _router.getAmountsOut(_amountIn, path)[path.length - 2] * config.slippageFactor() / 256 : 0;

        path[0].safeTransfer(address(factory.getPair(path[0], path[1])), _amountIn);
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(address(this));
        for (uint i; i < path.length - 1; i++) {
            (IERC20 input, IERC20 output) = (path[i], path[i + 1]);
            (IERC20 token0,) = sortTokens(input, output);
            bool inputIsToken0 = input == token0;
            
            IUniPair pair = factory.getPair(input, output);
            (uint reserve0, uint reserve1,) = pair.getReserves();

            (uint reserveInput, uint reserveOutput) = inputIsToken0 ? (reserve0, reserve1) : (reserve1, reserve0);
            uint amountInput = input.balanceOf(address(pair)) - reserveInput;
            uint amountOutput = _router.getAmountOut(amountInput, reserveInput, reserveOutput);

            (uint amount0Out, uint amount1Out) = inputIsToken0 ? (uint(0), amountOutput) : (amountOutput, uint(0));

            address to = i < path.length - 2 ? address(factory.getPair(output, path[i + 2])) : address(this);
            pair.swap(amount0Out, amount1Out, to, "");
        }
        
        if (amountOutMin > 0 && path[path.length - 1].balanceOf(address(this)) < amountOutMin + balanceBefore) {
            unchecked {
                revert InsufficientOutputAmount(path[path.length - 1].balanceOf(address(this)) - balanceBefore, amountOutMin);
            }
        }
    }

    function swapToWantToken(uint256 _amountIn, IERC20 _tokenA) internal {
        (IERC20 want,) = config.wantToken();
        if (config.isPairStake()) {
            (IERC20 token0, IERC20 token1) = config.token0And1();
            if (block.timestamp % 2 == 0) {
                safeSwap(_amountIn / 2, _tokenA, token0);
                safeSwap(_amountIn / 2, _tokenA, token1);
            } else {
                safeSwap(_amountIn / 2, _tokenA, token1);
                safeSwap(_amountIn / 2, _tokenA, token0);            
            }

            optimalMint(IUniPair(address(want)), token0, token1);
            
        } else {
            safeSwap(_amountIn, _tokenA, want);
        }
    }

    function optimalMint(IUniPair pair, IERC20 token0, IERC20 token1) internal returns (uint liquidity) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint totalSupply = pair.totalSupply();
        
        uint balance0 = token0.balanceOf(address(this));
        uint balance1 = token1.balanceOf(address(this));

        uint liquidity0 = balance0 * totalSupply / reserve0;
        uint liquidity1 = balance1 * totalSupply / reserve1;

        if (liquidity0 < liquidity1) {
            balance1 = reserve1 * balance0 / reserve0;
        } else {
            balance0 = reserve0 * balance1 / reserve1;
        }

        token0.safeTransfer(address(pair), balance0);
        token1.safeTransfer(address(pair), balance1);
        liquidity = pair.mint(address(this));
    }



    function configInfo() external view getConfig returns (ConfigInfo memory info) {

        (IERC20 want, uint wantDust) = config.wantToken();
        Tactics.TacticsA tacticsA = config.tacticsA();

        uint len = config.earnedLength();

        IERC20[] memory earned = new IERC20[](len);
        uint[] memory earnedDust = new uint[](len);
        for (uint i; i < len; i++) {
            (earned[i], earnedDust[i]) = config.earned(i);
        }

        info = ConfigInfo({
            vid: config.vid(),
            want: want,
            wantDust: wantDust,
            masterchef: Tactics.masterchef(tacticsA),
            pid: Tactics.pid(tacticsA),
            _router: config.router(),
            _magnetite: config.magnetite(),
            earned: earned,
            earnedDust: earnedDust,
            slippageFactor: config.slippageFactor(),
            feeOnTransfer: config.feeOnTransfer()
        });
    }


    function tactics() external view getConfig returns (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) {
        (tacticsA, tacticsB) = config.tactics();
    }

    function isMaximizer() external view getConfig returns (bool) {
        return config.isMaximizer();
    }

    //For IStrategy-conforming strategies who don't implement their own maximizers. Should revert if a strategy implementation
    //is incapable of being a maximizer.
    function getMaximizerImplementation() external virtual view returns (IStrategy) {
        return implementation;
    }

    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IStrategy).interfaceId;
    }

    function vaultSharesTotal() external view getConfig returns (uint256) {
        return _vaultSharesTotal();
    }


    function _vaultSharesTotal() internal view virtual returns (uint256) {
        return Tactics.vaultSharesTotal(config.tacticsA());
    }
    function _vaultDeposit(IERC20 _wantToken, uint256 _amount) internal virtual {   
        //token allowance for the pool to pull the correct amount of funds only
        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        _wantToken.safeIncreaseAllowance(address(bytes20(Tactics.TacticsA.unwrap(tacticsA))), _amount); //address(tacticsA >> 96) is masterchef        
        Tactics.deposit(tacticsA, tacticsB, _amount);
    }
    function _vaultWithdraw(IERC20 /*_wantToken*/, uint256 _amount) internal virtual {
        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        Tactics.withdraw(tacticsA, tacticsB, _amount);
    }
    function _vaultHarvest() internal virtual {
        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        Tactics.harvest(tacticsA, tacticsB); // Harvest farm tokens
    }
    function _vaultEmergencyWithdraw() internal virtual {
        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        Tactics.emergencyVaultWithdraw(tacticsA, tacticsB);
    }
}