// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;


import  { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";


abstract contract MonolithERC20 is IERC20Metadata {
    constructor(uint _transferFeeRate, address _transferFeeReceiver) {
        transferFeeRate = _transferFeeRate;
        transferFeeReceiver = _transferFeeReceiver;
    }
    
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 public transferFeeRate; // default 0.1% transfer fee
    address public transferFeeReceiver;
    uint256 public constant TRANSFER_FEE_MAX = 200; // maximum 2% transfer fee
    uint256 public constant BASIS_POINTS = 10000; // 100 = 1%
    
    string public override constant name = "CRYSTL Monolith Shards";
    string public override constant symbol = "mCRYSTL";
    uint8 public override constant decimals = 18;
    
    function totalSupply() public virtual override view returns (uint);
    
    function balanceOf(address account) public view virtual override returns (uint);
    
    function allowance(address owner, address spender) public override view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
        }

        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }
    
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal virtual;
}