// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./libraries/StrategyConfig.sol";
import "./interfaces/IStrategy.sol";
import "./libraries/Fee.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/VaultChonk.sol";
import "./libraries/AddrCalc.sol";

abstract contract BaseStrategy is IStrategy, ERC165 {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;
    using Fee for Fee.Data[3];

    uint constant FEE_MAX = 10000;
    uint16 constant CONFIG_POINTER = 0x200;
    StrategyConfig.MemPointer constant config = StrategyConfig.MemPointer.wrap(CONFIG_POINTER);
    IStrategy public immutable implementation;
    uint immutable WETH_DUST;
    uint constant LP_DUST = 2**16;
    IVaultHealer private _vaultHealer;

    constructor() {
        WETH_DUST = _getWethDust();
        implementation = this;
    }
	
	function _getWethDust() private view returns (uint) {
		if (block.chainid == 137 || block.chainid == 25 || block.chainid == 250) return 1e18;
		else if (block.chainid == 56) return 1e16;
		else return 1e14;
	}

    receive() external payable virtual { if (!Address.isContract(msg.sender)) revert Strategy_ImproperEthDeposit(msg.sender, msg.value); }

    //For VHv3.0 support. Returns the vaulthealer for a proxy; for an implementation, returns msg.sender to a contract or address(0) to an EOA
    function vaultHealer() external view returns (IVaultHealer) {
        return (implementation == this && msg.sender != tx.origin) ? IVaultHealer(msg.sender) : _vaultHealer;
    }

    modifier onlyVaultHealer { //must come after getConfig
        _requireVaultHealer();
        _;
    }
    function _requireVaultHealer() private view {
        //The address of this contract is a Cavendish create2 address with salt equal to the vid, and the VaultHealer is the deployer.
        //Address collisions are theoretically possible, but exceedingly rare. If one such false VaultHealer
        //address were calculated, it could not be used by anyone for the same reason that address(0) remains unclaimed.
        if (address(this) != Cavendish.computeAddress(bytes32(config.vid()), msg.sender)) revert Strategy_NotVaultHealer(msg.sender);
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

    function initialize(bytes memory _config) external virtual {
        if (this == implementation) revert Strategy_InitializeOnlyByProxy();
        address configAddr;
        assembly ("memory-safe") {
            let len := mload(_config) //get length of config
            mstore(_config, 0x600c80380380823d39803df3fe) //simple bytecode which saves everything after the f3
            configAddr := create(0, add(_config, 19), add(len,13)) //0 value; send 13 bytes plus _config
        }
        if (configAddr != configAddress()) revert Strategy_AlreadyInitialized(); //also checks that create didn't fail

        _vaultHealer = IVaultHealer(msg.sender);
        this.initialize_(); //must be called by this contract externally

    }

    function initialize_() external getConfig {
        require(msg.sender == address(this));
        _initialSetup();
    }
    
    function _initialSetup() internal virtual {
        IERC20 want = config.wantToken();

        _vaultSharesTotal();

		want.safeIncreaseAllowance(address(_vaultHealer), type(uint256).max);

        if (_isMaximizer()) {

            (IERC20 targetWant,,,,,) = _vaultHealer.vaultInfo(config.targetVid());
            if (want != targetWant) {
                for (uint i; i < config.earnedLength(); i++) {
                    (IERC20 earned,) = config.earned(i);
                    if (earned == targetWant) {
                        earned.safeIncreaseAllowance(address(_vaultHealer), type(uint256).max);
                        break;
                    }
                }
            }
        }
    }

    //should only happen when this contract deposits as a maximizer
    function onERC1155Received(
        address operator, address from, uint256 id, uint256, bytes calldata) external view returns (bytes4) {
        if (operator != address(this)) revert Strategy_Improper1155Deposit(operator, from, id);
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


    function router() external view getConfig returns (IUniRouter _router) { return config.router(); }
    function wantToken() external view getConfig returns (IERC20 _token) { return config.wantToken(); }
    function wantLockedTotal() external view getConfig returns (uint256) { return _wantLockedTotal(); }
    function _wantLockedTotal() internal view virtual returns (uint256) { return config.wantToken().balanceOf(address(this)) + _vaultSharesTotal(); }
    function configAddress() public view returns (address configAddr) { return AddrCalc.configAddress(); }

    //Safely deposits want tokens in farm
    function _farm() internal virtual {
        IERC20 _wantToken = config.wantToken();
        uint dust = config.wantDust();
        uint256 wantAmt = _wantToken.balanceOf(address(this));
        if (wantAmt > dust) {
        
			uint256 sharesBefore = _vaultSharesTotal();
			_vaultDeposit(_wantToken, wantAmt); //approves the transfer then calls the pool contract to deposit
			
			//safety check, will fail if there's a deposit fee rugpull or serious bug taking deposits
			if (_vaultSharesTotal() + _wantToken.balanceOf(address(this)) + dust < sharesBefore + wantAmt * config.slippageFactor() / 256)
				revert Strategy_ExcessiveFarmSlippage();
		}
    }

    function safeSwap(
        uint256 _amountIn,
        IERC20 _tokenA,
        IERC20 _tokenB
    ) internal {
        if (_tokenA == _tokenB || _amountIn == 0) return; //Do nothing for one-token paths
        IERC20[] memory path = config.magnetite().findAndSavePath(address(config.router()), _tokenA, _tokenB);
        require(path[0] == _tokenA && path[path.length - 1] == _tokenB, "Strategy: received invalid path for swap");
        safeSwap(_amountIn, path);
    }

    //returns true if the path from A to B contains weth; if true, path from tokenA to weth
    //otherwise, path from tokenA to tokenB
    function wethOnPath(IERC20 _tokenA, IERC20 _tokenB) internal returns (bool containsWeth, IERC20[] memory path) {
        IERC20 weth = config.weth();
        if (_tokenA == weth) {
            path = new IERC20[](1);
            path[0] = weth;
            return (true, path);
        } else {
            path = config.magnetite().findAndSavePath(address(config.router()), _tokenA, _tokenB);
            if (_tokenB == weth) return (true, path);
            else {
                for (uint i = 1; i < path.length - 1; i++) {
                    if (path[i] == weth) {
                        assembly("memory-safe") { mstore(path, add(i,1)) } //truncate path at weth
                        return (true, path);
                    }
                }
            }
        }
    }

    function safeSwap(
        uint256 _amountIn,
        IERC20[] memory path
    ) internal virtual {
        if (_amountIn == 0 || path.length < 2) return;
        IUniRouter _router = config.router();
        IUniFactory factory = _router.factory();

        uint[] memory amounts = _router.getAmountsOut(_amountIn, path);
        IUniPair pair = factory.getPair(path[0], path[1]);
        path[0].safeTransfer(address(pair), _amountIn);
        
        if (config.feeOnTransfer()) {
            uint balanceBefore = path[path.length - 1].balanceOf(address(this));

            for (uint i = 1; i < path.length; i++) {
                (uint reserve0, uint reserve1,) = pair.getReserves();
                
                (uint amount0Out, uint amount1Out) = path[i - 1] < path[i] ? 
                    (uint(0), _router.getAmountOut(path[i - 1].balanceOf(address(pair)) - reserve0, reserve0, reserve1)) :
                    (_router.getAmountOut(path[i - 1].balanceOf(address(pair)) - reserve1, reserve1, reserve0), uint(0));

                if (i == path.length - 1) {
                    pair.swap(amount0Out, amount1Out, address(this), "");
                } else {
                    IUniPair nextPair = factory.getPair(path[i], path[i + 1]);
                    pair.swap(amount0Out, amount1Out, address(nextPair), "");
                    pair = nextPair;
                }
            }
            uint amountOutMin = amounts[amounts.length - 1] * config.slippageFactor() / 256;
            uint amountOutput = path[path.length - 1].balanceOf(address(this)) - balanceBefore;
            if (amountOutput < amountOutMin) revert InsufficientOutputAmount(amountOutput, amountOutMin);

        } else {
            
            for (uint i = 1; i < path.length; i++) {
                (uint amount0Out, uint amount1Out) = path[i - 1] < path[i] ? (uint(0), amounts[i]) : (amounts[i], uint(0));
                
                if (i == path.length - 1) {
                    pair.swap(amount0Out, amount1Out, address(this), "");
                } else {
                    IUniPair nextPair = factory.getPair(path[i], path[i + 1]);
                    pair.swap(amount0Out, amount1Out, address(nextPair), "");
                    pair = nextPair;
                }
            }
        }
    }

    function swapToWantToken(uint256 _amountIn, IERC20 _tokenA) internal {
        IERC20 want = config.wantToken();

        if (config.isPairStake()) {
            (IERC20 token0, IERC20 token1) = config.token0And1();

            if (block.timestamp % 2 == 0) {
                safeSwap(_amountIn / 2, _tokenA, token0);
                safeSwap(_amountIn / 2, _tokenA, token1);
            } else {
                safeSwap(_amountIn / 2, _tokenA, token1);
                safeSwap(_amountIn / 2, _tokenA, token0);            
            }

            mintPair(IUniPair(address(want)), token0, token1);
            
        } else {
            safeSwap(_amountIn, _tokenA, want);
        }
    }

    function mintPair(IUniPair pair, IERC20 token0, IERC20 token1) internal returns (uint liquidity) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        pair.skim(address(this));
        
        uint balance0 = token0.balanceOf(address(this));
        uint balance1 = token1.balanceOf(address(this));

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        (uint amount0, uint amount1) = (balance0 * reserve1 < balance1 * reserve0) ?
            (balance0, balance0 * reserve1 / reserve0) :
            (balance1 * reserve0 / reserve1, balance1);

        if (amount0 * amount1 > 0) { //if both are nonzero
            token0.safeTransfer(address(pair), amount0);
            token1.safeTransfer(address(pair), amount1);
            liquidity = pair.mint(address(this));
            balance0 -= amount0;
            balance1 -= amount1;
        }

        if (balance0 > LP_DUST) {
            IERC20[] memory path = new IERC20[](2);
            (path[0], path[1]) = (token0, token1);
            safeSwap(balance0 / 3, path);
        } else if (balance1 > LP_DUST) {
            IERC20[] memory path = new IERC20[](2);
            (path[0], path[1]) = (token1, token0);
            safeSwap(balance1 / 3, path);
        }
    }

    function configInfo() external view getConfig returns (ConfigInfo memory info) {

        Tactics.TacticsA tacticsA = config.tacticsA();

        uint len = config.earnedLength();

        IERC20[] memory earned = new IERC20[](len);
        uint[] memory earnedDust = new uint[](len);
        for (uint i; i < len; i++) {
            (earned[i], earnedDust[i]) = config.earned(i);
        }

        info = ConfigInfo({
            vid: config.vid(),
            want: config.wantToken(),
            wantDust: config.wantDust(),
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
        return _isMaximizer();
    }

    //For IStrategy-conforming strategies who don't implement their own maximizers. Should revert if a strategy implementation
    //is incapable of supporting a maximizer.
    function getMaximizerImplementation() external virtual view returns (IStrategy) {
        revert Strategy_MaximizersNotSupported();
    }
    function _isMaximizer() internal virtual view returns (bool) { 
        assert(!config.isMaximizer());
        return false; 
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
        _wantToken.safeIncreaseAllowance(Tactics.masterchef(tacticsA), _amount);      
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

    function wrapAllEth() internal {
        if (address(this).balance > WETH_DUST) {
            config.weth().deposit{value: address(this).balance}();
        }
    }
    function unwrapAllWeth() internal returns (bool hasEth) {
        IWETH weth = config.weth();
        uint wethBal = weth.balanceOf(address(this));
        if (wethBal > WETH_DUST) {
            weth.withdraw(wethBal);
            return true;
        }
        return address(this).balance > WETH_DUST;
    }
	
    function sellUnwanted(IERC20 tokenOut, uint amount) internal {
        IERC20[] memory path;
        bool toWeth;
        if (config.isPairStake()) {
            (IERC20 token0, IERC20 token1) = config.token0And1();
            (toWeth, path) = wethOnPath(tokenOut, token0);
            (bool toWethToken1,) = wethOnPath(tokenOut, token1);
            toWeth = toWeth && toWethToken1;
        } else {
            (toWeth, path) = wethOnPath(tokenOut, config.wantToken());
        }
        if (toWeth) safeSwap(amount, path); //swap to the native gas token if it's on the path
        else swapToWantToken(amount, tokenOut);
    }

    function _sync() internal virtual {}

    function earn(Fee.Data[3] calldata fees, address operator, bytes calldata data) external getConfig onlyVaultHealer returns (bool success, uint256 __wantLockedTotal) {
        IERC20 _wantToken = config.wantToken();
        uint wantLockedBefore = _wantToken.balanceOf(address(this)) + _vaultSharesTotal();
        success = _earn(fees, operator, data);
		__wantLockedTotal = _wantToken.balanceOf(address(this)) + _vaultSharesTotal();
        if (__wantLockedTotal < wantLockedBefore) revert Strategy_WantLockedLoss();
    }
    function _earn(Fee.Data[3] calldata fees, address operator, bytes calldata data) internal virtual returns (bool success);

    //VaultHealer calls this to add funds at a user's direction. VaultHealer manages the user shares
    function deposit(uint256 _wantAmt, uint256 _sharesTotal, bytes calldata) public virtual payable getConfig onlyVaultHealer returns (uint256 wantAdded, uint256 sharesAdded) {
        _sync();
		_farm();
        IERC20 _wantToken = config.wantToken();
        uint wantLockedBefore = _vaultSharesTotal() + _wantToken.balanceOf(address(this));

        if (msg.value > 0) {
            IWETH weth = config.weth();
            weth.deposit{value: msg.value}();
            swapToWantToken(msg.value, weth);
        }

        //Before calling deposit here, the vaulthealer records how much the user deposits. Then with this
        //call, the strategy tells the vaulthealer to proceed with the transfer. This minimizes risk of
        //a rogue strategy 
        if (_wantAmt > 0) IVaultHealer(msg.sender).executePendingDeposit(address(this), uint192(_wantAmt));
        _farm(); //deposits the tokens in the pool
        // Proper deposit amount for tokens with fees, or vaults with deposit fees

        wantAdded = _wantToken.balanceOf(address(this)) + _vaultSharesTotal() - wantLockedBefore;
        sharesAdded = _sharesTotal == 0 ? wantAdded : Math.ceilDiv(wantAdded * _sharesTotal, wantLockedBefore);
        if (wantAdded < config.wantDust() || sharesAdded == 0) revert Strategy_DustDeposit(wantAdded);
    }

    //Correct logic to withdraw funds, based on share amounts provided by VaultHealer
    function withdraw(uint _wantAmt, uint _userShares, uint _sharesTotal, bytes calldata) public virtual getConfig onlyVaultHealer returns (uint sharesRemoved, uint wantAmt) {
        _sync();
        IERC20 _wantToken = config.wantToken();
        uint wantBal = _wantToken.balanceOf(address(this)); 
        uint wantLockedBefore = wantBal + _vaultSharesTotal();
        uint256 userWant = _userShares * wantLockedBefore / _sharesTotal; //User's balance, in want tokens
        
        // user requested all, very nearly all, or more than their balance, so withdraw all
        unchecked { //overflow is caught and handled in the second condition
            uint dust = config.wantDust();
            if (_wantAmt + dust > userWant || _wantAmt + dust < _wantAmt) {
				_wantAmt = userWant;
            }
        }

		uint withdrawSlippage;
        if (_wantAmt > wantBal) {
            uint toWithdraw = _wantAmt - wantBal;
            _vaultWithdraw(_wantToken, toWithdraw); //Withdraw from the masterchef, staking pool, etc.
            wantBal = _wantToken.balanceOf(address(this));
			uint wantLockedAfter = wantBal + _vaultSharesTotal();
			
			//Account for reflect, pool withdraw fee, etc; charge these to user
			withdrawSlippage = wantLockedAfter < wantLockedBefore ? wantLockedBefore - wantLockedAfter : 0;
		}
		
		//Calculate shares to remove
        sharesRemoved = (_wantAmt + withdrawSlippage) * _sharesTotal;
        sharesRemoved = Math.ceilDiv(sharesRemoved, wantLockedBefore);
		
        //Get final withdrawal amount
        if (sharesRemoved > _userShares) {
            sharesRemoved = _userShares;
        }
		wantAmt = sharesRemoved * wantLockedBefore / _sharesTotal;
        
        if (wantAmt <= withdrawSlippage) revert Strategy_TotalSlippageWithdrawal(); //nothing to withdraw after slippage
		
		wantAmt -= withdrawSlippage;
		if (wantAmt > wantBal) wantAmt = wantBal;
		
        return (sharesRemoved, wantAmt);

    }

    function generateConfig(
        Tactics.TacticsA _tacticsA,
        Tactics.TacticsB _tacticsB,
        address _wantToken,
        uint8 _wantDust,
        address _router,
        address _magnetite,
        uint8 _slippageFactor,
        bool _feeOnTransfer,
        address[] memory _earned,
        uint8[] memory _earnedDust
    ) public virtual view returns (bytes memory configData) {
        require(_earned.length < 0x20, "earned.length invalid");
        require(_earned.length == _earnedDust.length, "earned/dust length mismatch");
        uint8 vaultType = uint8(_earned.length);
        if (_feeOnTransfer) vaultType += 0x80;
        configData = abi.encodePacked(_tacticsA, _tacticsB, _wantToken, _wantDust, _router, _magnetite, _slippageFactor);
		
		IERC20 _targetWant = IERC20(_wantToken);

        //Look for LP tokens. If not, want must be a single-stake
        try IUniPair(address(_targetWant)).token0() returns (IERC20 _token0) {
            vaultType += 0x20;
            IERC20 _token1 = IUniPair(address(_targetWant)).token1();
            configData = abi.encodePacked(configData, vaultType, _token0, _token1);
        } catch { //if not LP, then single stake
            configData = abi.encodePacked(configData, vaultType);
        }

        for (uint i; i < _earned.length; i++) {
            configData = abi.encodePacked(configData, _earned[i], _earnedDust[i]);
        }

        configData = abi.encodePacked(configData, IUniRouter(_router).WETH());
    }

    function generateTactics(
        address _masterchef,
        uint24 pid, 
        uint8 vstReturnPosition, 
        bytes8 vstCode, //includes selector and encoded call format
        bytes8 depositCode, //includes selector and encoded call format
        bytes8 withdrawCode, //includes selector and encoded call format
        bytes8 harvestCode, //includes selector and encoded call format
        bytes8 emergencyCode//includes selector and encoded call format
    ) external virtual pure returns (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) {
        tacticsA = Tactics.TacticsA.wrap(bytes32(abi.encodePacked(bytes20(_masterchef),bytes3(pid),bytes1(vstReturnPosition),vstCode)));
        tacticsB = Tactics.TacticsB.wrap(bytes32(abi.encodePacked(depositCode, withdrawCode, harvestCode, emergencyCode)));
    }

}