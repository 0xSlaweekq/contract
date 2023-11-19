// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract EtherWarsToken is ERC20, Ownable {
  uint256 private _totalSupply = 1811250 * (10 ** 18);

  constructor() ERC20('SETH', 'SETH') {
    _mint(msg.sender, _totalSupply);
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
