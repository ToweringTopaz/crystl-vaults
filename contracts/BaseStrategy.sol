// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./libraries/StrategyConfig.sol";
import "./interfaces/IStrategy.sol";

/// @title Crystl Vaults v3 BaseStrategy
/// @author ToweringTopaz, RichJamo, with some traces of residual code from Polycat
/// @notice Provides the low-level implementation supporting the generic strategy contract, which interfaces with yield farms
abstract contract BaseStrategy is IStrategy, ERC165 {
    using SafeERC20 for IERC20;
    using StrategyConfig for StrategyConfig.MemPointer;


    uint constant FEE_MAX = 10000;
    StrategyConfig.MemPointer constant config = StrategyConfig.MemPointer.wrap(0x80);
    
    /// @notice The address of the associated VaultHealer contract. Most functions are only accessible with the VaultHealer acting as an intermediary.
    address public immutable vaultHealer;

    /// @notice The address of this contract's implementation.
    /// @dev Can be used to check whether the active contract is a proxy. If so, implementation != address(this)
    address public immutable implementation;

    constructor(address _vaultHealer) { 
        vaultHealer = _vaultHealer;
        implementation = address(this);
    }

    /// @notice Generally ether (or other native gas token) should not be sent to this address. Prevents anything that isn't a contract from doing so.
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
        //  if gt(mload(0x40), 0x80) { // asserting that this function is only called once at the beginning of every incoming call
        //           revert(0,0)        // we keep these 3 lines in, commented, as they're useful for building and testing
        //    }
            let len := sub(extcodesize(configAddr), 1) //get length, subtracting 1 for the invalid opcode
            mstore(0x40, add(0x80, len)) //update free memory pointer
            extcodecopy(configAddr, 0x80, 1, len) //get the data
        }
    }

    /// @notice Used when creating a new vault
    /// @dev Called once by VaultHealer after a new strategy proxy is deployed
    function initialize(bytes memory _config) external onlyVaultHealer {
        require(address(this) != implementation, "Strategy: This contract must be used by proxy");
        assembly {
            let len := mload(_config) //get length of config
            mstore(_config, 0x600c80380380823d39803df3fe) //simple bytecode which saves everything after the f3

            let configAddr := create(0, add(_config, 19), add(len,13)) //0 value; send 13 bytes plus _config
            if iszero(configAddr) { //create failed?
                revert(0, 0)
            }
        }
		_getConfig();
		(IERC20 _wantToken,) = config.wantToken();
		_wantToken.safeIncreaseAllowance(msg.sender, type(uint256).max);
		IERC20 _targetWant = config.targetWant();

		if (_wantToken != _targetWant) _targetWant.safeIncreaseAllowance(msg.sender, type(uint256).max);
    }

    /// @notice Allows a maximizer strategy to receive ERC1155 tokens representing shares of its target vault
    function onERC1155Received(
        address operator, address from, uint256 id, uint256, bytes calldata) external view onlyVaultHealer getConfig returns (bytes4) {
        require (operator == address(this) && from == address(0) && id == config.vid() >> 16, "Strategy: Improper ERC1155 deposit");
        return 0xf23a6e61;
    }

    /// @notice Reverts, because there is currently no support for strategies to hold more than one ERC1155 token ID.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        revert("Strategy: Batch transfers not supported here");
    }

    // @notice If there is an unforeseen threat to user funds, VaultHealer administrators may order the strategy to panic, emergency-withdrawing all deposited funds
    function panic() external getConfig onlyVaultHealer {
        (Tactics.TacticsA tacticsA, Tactics.TacticsB tacticsB) = config.tactics();
        Tactics.emergencyVaultWithdraw(tacticsA, tacticsB);
    }
    // @notice Returns to normal behavior, following a panic
    function unpanic() external getConfig onlyVaultHealer { 
        _farm();
    }

    // @notice The uniswapv2 compatible router this strategy uses for performing token swaps
    function router() external view getConfig returns (IUniRouter _router) {
        return config.router();
    }

    // @notice The token this strategy invests as its principal
    function wantToken() external view getConfig returns (IERC20 _token) {
        (_token,) = config.wantToken();
    }

    // @notice The address of a pseudo-contract which, rather than code, contains all configuration data for this strategy
    function configAddress() public view returns (address configAddr) {
        assembly {
            mstore(0, or(0xd694000000000000000000000000000000000000000001000000000000000000, shl(80,address())))
            configAddr := and(0xffffffffffffffffffffffffffffffffffffffff, keccak256(0, 23)) //create address, nonce 1
        }
    }

    // @notice The amount of tokens currently invested by this vault
    function vaultSharesTotal() external view getConfig returns (uint256) {
        return _vaultSharesTotal();
    }
    function _vaultSharesTotal() internal view virtual returns (uint256) {
        return Tactics.vaultSharesTotal(config.tacticsA());
    }

    // @notice The amount of tokens currently invested by this vault, plus any uninvested tokens it holds
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
        require(sharesAfter + _wantToken.balanceOf(address(this)) + dust >= (sharesBefore + wantAmt) * config.slippageFactor() / 256,
            "High vault deposit slippage");
        return;
    }

    /// @notice Used by the earn function to collect and pay out fees
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
            
            IWETH weth = _router.WETH();
            
            if (_earnedToken == weth) {
                weth.withdraw(feeEarnedAmt);    
            } else {
                uint wethBefore = weth.balanceOf(address(this));
                safeSwap(feeEarnedAmt, _earnedToken, weth, address(this));
                weth.withdraw(weth.balanceOf(address(this)) - wethBefore);
            }
            
            //This contract should not hold native between transactions but it could happen theoretically. Pay it out with the fees
            if (address(this).balance > 0) {
                uint feeNativeAmt = address(this).balance;
                for (uint i; i < 3; i++) {
                    (address receiver, uint rate) = Fee.receiverAndRate(fees[i]);
                    if (receiver == address(0) || rate == 0) break;
                    (bool success,) = receiver.call{value: feeNativeAmt * rate / feeTotalRate, gas: 0x40000}("");
                    require(success, "Strategy: Transfer failed");
                }
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

        //allow swap._router to pull the correct amount in
        IERC20(_tokenA).safeIncreaseAllowance(address(_router), _amountIn);

        if (config.feeOnTransfer()) {
            _router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn, 
                _router.getAmountsOut(_amountIn, path)[path.length - 2] * config.slippageFactor() / 256,
                path,
                _to, 
                block.timestamp
            );
        } else {
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