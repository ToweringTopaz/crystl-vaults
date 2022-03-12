// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./VaultHealerBase.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/PRBMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


abstract contract VaultHealerGate is VaultHealerBase {
    using SafeERC20 for IERC20;

    struct PendingDeposit {
        IERC20 token;
        uint96 amount0;
        address from;
        uint96 amount1;
    }
    mapping(address => mapping(uint256 => uint256)) public maximizerEarningsOffset;
    mapping(uint256 => uint256) public totalMaximizerEarningsOffset;

    mapping(address => PendingDeposit) private pendingDeposits;

    //For front-end and general purpose external compounding. Returned amounts are zero on failure, or the gas cost on success
    function earn(uint256[] calldata vids) external nonReentrant returns (uint[] memory successGas) {
        Fee.Data[3][] memory fees = vaultFeeManager.getEarnFees(vids);
        successGas = new uint[](vids.length);
        for (uint i; i < vids.length; i++) {
            uint gasBefore = gasleft();
            if (_earn(vids[i], fees[i], msg.data[0:0])) successGas[i] = gasBefore - gasleft();
        }
    }
    function earn(uint256[] calldata vids, bytes[] calldata data) external nonReentrant returns (uint[] memory successGas) {
        require(vids.length == data.length, "VH: input array mismatch");
        Fee.Data[3][] memory fees = vaultFeeManager.getEarnFees(vids);
        successGas = new uint[](vids.length);
        for (uint i; i < vids.length; i++) {
            uint gasBefore = gasleft();
            if (_earn(vids[i], fees[i], data[i])) successGas[i] = gasBefore - gasleft();
        }
    }

    function _earn(uint256 vid, Fee.Data[3] memory fees, bytes calldata data) internal returns (bool) {
        console.log("earn blocknum", block.number);
        VaultInfo storage vault = vaultInfo[vid];
        if (!vault.active || vault.lastEarnBlock == block.number) return false;

        vault.lastEarnBlock = uint48(block.number);
        try strat(vid).earn(fees, _msgSender(), data) returns (bool success, uint256 wantLockedTotal) {
            if (success) {                
                emit Earned(vid, wantLockedTotal);
                return true;
            } else console.log("earn !success");
        } catch Error(string memory reason) {
            emit FailedEarn(vid, reason);
            console.log("failed earn:", reason);
        } catch (bytes memory reason) {
            emit FailedEarnBytes(vid, reason);
        }
        return false;
    }
    
    //Allows maximizers to make reentrant calls, only to deposit to their target
    function maximizerDeposit(uint _vid, uint _wantAmt, bytes calldata _data) external payable whenNotPaused(_vid) {
        address sender = _msgSender();
        require(address(strat(_vid)) == sender, "VH: sender does not match vid");
        //totalMaximizerEarningsOffset[_vid] += 
        _deposit(_vid >> 16, _wantAmt, sender, sender, _data);
		console.log("maxideposit:", _vid, balanceOf(_msgSender(), _vid >> 16));
    }

    // Want tokens moved from user -> this -> Strat (compounding
    function deposit(uint256 _vid, uint256 _wantAmt, bytes calldata _data) external payable whenNotPaused(_vid) nonReentrant {
        _deposit(_vid, _wantAmt, _msgSender(), _msgSender(), _data);
    }

    // For depositing for other users
    function deposit(uint256 _vid, uint256 _wantAmt, address _to, bytes calldata _data) external payable whenNotPaused(_vid) nonReentrant {
        _deposit(_vid, _wantAmt, _msgSender(), _to, _data);
    }

    function _deposit(uint256 _vid, uint256 _wantAmt, address _from, address _to, bytes calldata _data) private returns (uint256 vidSharesAdded) {
        console.log("deposit blocknum", block.number);
        VaultInfo memory vault = vaultInfo[_vid];
        // If enabled, we call an earn on the vault before we action the _deposit
        if (vault.noAutoEarn & 1 == 0) _earn(_vid, vaultFeeManager.getEarnFees(_vid), _data); 

        IStrategy vaultStrat = strat(_vid);

        if (_wantAmt > 0 && address(vault.want) != address(0)) pendingDeposits[address(vaultStrat)] = PendingDeposit({
            token: vault.want,
            amount0: uint96(_wantAmt >> 96),
            from: _from,
            amount1: uint96(_wantAmt)
        });
        
        uint256 totalSupplyBefore = totalSupply(_vid);
        // if this is a maximizer vault, do these extra steps
        if (_vid > 2**16 && totalSupplyBefore > 0) maximizerHarvest(_to, _vid);

        // we make the deposit
        uint256 wantAdded;
        (wantAdded, vidSharesAdded) = vaultStrat.deposit{value: msg.value}(_wantAmt, totalSupplyBefore, abi.encode(_msgSender(), _from, _to, _data));

        //we mint tokens for the user via the 1155 contract
        _mint(
            _to,
            _vid, //use the vid of the strategy 
            vidSharesAdded,
            _data
        );
		
        if (_vid > 2**16 && totalSupplyBefore > 0) maximizerUpdate(_to, _vid);

        emit Deposit(_from, _to, _vid, wantAdded);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _vid, uint256 _wantAmt, bytes calldata _data) external nonReentrant {
        _withdraw(_vid, _wantAmt, _msgSender(), _msgSender(), _data);
    }

    function withdraw(uint256 _vid, uint256 _wantAmt, address _from, address _to, bytes calldata _data) external nonReentrant {
        require(
            _from == _msgSender() || isApprovedForAll(_from, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        _withdraw(_vid, _wantAmt, _from, _to, _data);
    }
	
	error WithdrawZeroBalance(address from);

    function _withdraw(uint256 _vid, uint256 _wantAmt, address _from, address _to, bytes calldata _data) private {
		uint fromBalance = balanceOf(_from, _vid);
        if (fromBalance == 0) {
			console.log("bad withdraw: ", _vid, _from);
			console.log("amount: ", _wantAmt);
			revert WithdrawZeroBalance(_from);
		}
        
        VaultInfo memory vault = vaultInfo[_vid];

        // we call an earn on the vault before we action the _deposit
        if (vault.noAutoEarn & 2 == 0) _earn(_vid, vaultFeeManager.getEarnFees(_vid), _data); 

        IStrategy vaultStrat = strat(_vid);

        (uint256 vidSharesRemoved, uint256 wantAmt) = vaultStrat.withdraw(_wantAmt, fromBalance, totalSupply(_vid), abi.encode(_msgSender(), _from, _to, _data));
        
        if (_vid > 2**16) maximizerHarvest(_from, _vid);
		
        //burn the tokens equal to vidSharesRemoved
        _burn(
            _from,
            _vid,
            vidSharesRemoved
        );
        
		assert(vault.want.balanceOf(address(vaultStrat)) >= wantAmt);
		
        //withdraw fee is implemented here
        try vaultFeeManager.getWithdrawFee(_vid) returns (address feeReceiver, uint16 feeRate) {
            //hardcoded 3% max fee rate
            if (feeReceiver != address(0) && feeRate <= 300 && !paused(_vid)) { //waive withdrawal fee on paused vaults as there's generally something wrong
                uint feeAmt = wantAmt * feeRate / 10000;
                wantAmt -= feeAmt;
                vault.want.safeTransferFrom(address(vaultStrat), feeReceiver, feeAmt);
            }
        } catch Error(string memory reason) {
            emit FailedWithdrawFee(_vid, reason);
        } catch (bytes memory reason) {
            emit FailedWithdrawFeeBytes(_vid, reason);
        }

        //this call transfers wantTokens from the strat to the user
		assert(vault.want.balanceOf(address(vaultStrat)) >= wantAmt);

        vault.want.safeTransferFrom(address(vaultStrat), _to, wantAmt);

        if (_vid > 2**16) maximizerUpdate(_from, _vid);

        emit Withdraw(_from, _to, _vid, wantAmt);
    }
	
    //called by strategy, cannot be nonReentrant
    function executePendingDeposit(address _to, uint192 _amount) external {
        IERC20 token = pendingDeposits[msg.sender].token;
        uint amount0 = pendingDeposits[msg.sender].amount0;
        address from = pendingDeposits[msg.sender].from;
        uint amount1 = pendingDeposits[msg.sender].amount1;
        require(_amount <= amount0 << 96 | amount1, "VH: strategy requesting more tokens than authorized");
        delete pendingDeposits[msg.sender];

        token.safeTransferFrom(
            from,
            _to,
            _amount
        );
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        if (from != address(0) && to != address(0)) {
            for (uint i; i < ids.length; i++) {
                uint vid = ids[i];

                if (vid > 2**16) {
                    _earn(vid, vaultFeeManager.getEarnFees(vid), msg.data[0:0]);
                    maximizerHarvest(from, vid);
					if (from != to) maximizerHarvest(to, vid);
                }

            }
        }
    }
	
    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual override {
		super._safeTransferFrom(from, to, id, amount, data);
		if (id > 2**16) {
			maximizerUpdate(from, id);
			if (from != to) maximizerUpdate(to, id);
		}
	}

    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
		super._safeBatchTransferFrom(from, to, ids, amounts, data);
		for (uint i; i < ids.length; i++) {
			uint vid = ids[i];
			if (vid > 2**16) {
				maximizerUpdate(from, vid);
				if (from != to) maximizerUpdate(to, vid);
			}
		}
	}

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function maximizerUpdate(address _account, uint256 _vid) internal {
        uint256 targetVid = _vid >> 16;
		if (targetVid == 0) return;

		if (totalSupply(_vid) == 0) {
			maximizerEarningsOffset[_account][_vid] = 0;
			totalMaximizerEarningsOffset[_vid] = 0;
		} else {
			uint totalOffset = totalMaximizerEarningsOffset[_vid];
			uint256 userOffsetAfter = Math.ceilDiv(balanceOf(_account, _vid) * (balanceOf(address(strat(_vid)), targetVid) + totalOffset), totalSupply(_vid));
			uint userOffsetBefore = maximizerEarningsOffset[_account][_vid];
			maximizerEarningsOffset[_account][_vid] = userOffsetAfter;
			console.log("userOffsetAfter: ", userOffsetAfter);
			totalMaximizerEarningsOffset[_vid] = totalOffset + userOffsetAfter - userOffsetBefore;
		}

    }

    // // For maximizer vaults, this function helps us keep track of each users' claim on the tokens in the target vault
    function maximizerHarvest(address _account, uint256 _vid) internal {
        uint targetVid = _vid >> 16;
		if (targetVid == 0) return;
		
        // calculate the amount of targetVid shares to be withdrawn		
		uint targetVidShares = maximizerRawTargetShares(_account, _vid);
		uint accountOffset = maximizerEarningsOffset[_account][_vid];
		
		if (targetVidShares > accountOffset) {
			
			uint sharesEarned = targetVidShares - accountOffset;
			totalMaximizerEarningsOffset[_vid] += sharesEarned;
			maximizerEarningsOffset[_account][_vid] = targetVidShares;
			console.log("targetVidShares: ", targetVidShares);
			_safeTransferFrom(address(strat(_vid)), _account, targetVid, sharesEarned, "");
		    emit MaximizerWithdraw(_account, _vid, sharesEarned);
		}
     }
	 
	function maximizerRawTargetShares(address _account, uint256 _vid) internal view returns (uint256) {
        uint targetVid = _vid >> 16;
		if (targetVid == 0) return 0;

		uint userVaultBalance = balanceOf(_account, _vid);
		if (userVaultBalance == 0) return 0;		
		
		return userVaultBalance * (balanceOf(address(strat(_vid)), targetVid) + totalMaximizerEarningsOffset[_vid]) / totalSupply(_vid);
	}
	
	function maximizerPendingTargetShares(address _account, uint256 _vid) public view returns (uint256) {
		uint targetVidShares = maximizerRawTargetShares(_account, _vid);
		uint accountOffset = maximizerEarningsOffset[_account][_vid];
		
		return targetVidShares > accountOffset ? targetVidShares - accountOffset : 0;
	}
	
	function totalBalanceOf(address _account, uint256 _vid) external view returns (uint256 amount) {
		amount = super.balanceOf(_account, _vid);
		uint lastMaximizer = (_vid << 16) + vaultInfo[_vid].numMaximizers;
		for (uint i = (_vid << 16) + 1; i <= lastMaximizer; i++) {
			amount += maximizerPendingTargetShares(_account, i);
		}
		console.log("total balance: ", amount);
	}
}
