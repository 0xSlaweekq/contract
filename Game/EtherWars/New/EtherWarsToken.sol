// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract EtherWarsToken is ERC20, Ownable {
    uint256 private _totalSupply = 3 * 10**6 * (10**18);

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    constructor() ERC20('Ether Wars', 'eWars') {
        _mint(msg.sender, _totalSupply);
    }

    receive() external payable {
        revert();
    }

    function isApprove(address owner, address spender) public view virtual returns (bool) {
        return _operatorApprovals[owner][spender];
    }

    function recover() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
