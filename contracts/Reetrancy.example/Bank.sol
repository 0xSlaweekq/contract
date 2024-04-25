// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*
Bank is a contract where you can deposit and withdraw ETH.
This contract is vulnerable to re-entrancy attack.
Let's see why.

1. Deploy Bank
2. Deposit 1 Ether each from Account 1 (Alice) and Account 2 (Bob) into Bank
3. Deploy Attack with address of Bank
4. Call Attack.attack sending 1 ether (using Account 3 (Eve)).
   You will get 3 Ethers back (2 Ether stolen from Alice and Bob,
   plus 1 Ether sent from this contract).

What happened?
Attack was able to call Bank.withdraw multiple times before
Bank.withdraw finished executing.

Here is how the functions were called
- Attack.attack
- Bank.deposit
- Bank.withdraw
- Attack fallback (receives 1 Ether)
- Bank.withdraw
- Attack.fallback (receives 1 Ether)
- Bank.withdraw
- Attack fallback (receives 1 Ether)
*/

contract Bank is ReentrancyGuard {
    mapping(address => uint) public balances;

    function deposit() public payable {
        balances[msg.sender] += msg.value;
    }

    //TODO add this modifier nonReentrant for secured transaction
    function withdraw() public {
        uint bal = balances[msg.sender];
        require(bal > 0);

        (bool sent, ) = msg.sender.call{value: bal}("");
        require(sent, "Failed to send Ether");

        balances[msg.sender] = 0;
    }

    // Helper function to check the balance of this contract
    function getBalanceBank() public view returns (uint) {
        return address(this).balance;
    }
}
