// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "../@openzeppelin/access/AccessControl.sol";
import "../@openzeppelin/token/ERC20/IERC20.sol";
import "../@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "../@openzeppelin/token/ERC20/utils/SafeERC20.sol";

abstract contract ERC20 is AccessControl, IERC20, IERC20Metadata {
    using SafeERC20 for IERC20;
    bytes32 public constant GOVERN_ROLE = keccak256("GOVERN_ROLE");

    mapping(address => mapping(address => uint256)) internal _allowances;
    mapping(address => uint256) internal _balances;

    string public name;
    string public symbol;

    uint256 public totalSupply;
    uint8 public decimals = 18;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /// @notice recover any trapped tokens, guard against recovering this token from contract
    function reclaim(
        address tokenAddr_,
        uint256 amt_
    ) external payable onlyRole(GOVERN_ROLE) {
        if (tokenAddr_ == address(0)) {
            uint256 amt = address(this).balance;
            (bool sent, ) = _msgSender().call{value: amt}("");
            require(sent);
        } else {
            require(tokenAddr_ != address(this));
            IERC20 token = IERC20(tokenAddr_);
            uint256 balance = (token.balanceOf(address(this)));
            if (amt_ > balance) {
                amt_ = balance;
            }
            token.safeTransfer(_msgSender(), amt_);
        }
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        address spender = _msgSender();
        uint256 currAllowance = _allowances[from][spender];
        if (currAllowance != type(uint256).max) {
            require(currAllowance >= amount, "IA");
            unchecked {
                _allowances[from][spender] = currAllowance - amount;
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ABZ");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "FZA");
        require(to != address(0), "TZA");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "AEB");
        unchecked {
            _balances[from] = fromBalance - amount;
        // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
        // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "MTZ");

        totalSupply += amount;
        unchecked {
        // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "FZA");
        require(spender != address(0), "TZA");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}
