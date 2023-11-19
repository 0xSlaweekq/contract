// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract ForceToken is ERC20, Ownable {
  constructor() ERC20('Force', 'FORCE') {
    _mint(msg.sender, 10e8 * (10 ** 18));
  }

  receive() external payable {
    revert();
  }

  function isApproved(address owner, address spender) public view virtual returns (bool) {
    if (allowance(owner, spender) >= balanceOf(owner)) return true;
    return false;
  }

  function recover() external onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }
}
