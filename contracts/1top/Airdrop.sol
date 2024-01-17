// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

abstract contract ReentrancyGuard {
    bool private _notEntered;

    constructor() {
        _notEntered = true;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_notEntered, "ReentrancyGuard: reentrant call");
        // Any calls to nonReentrant after this point will fail
        _notEntered = false;
        _;
        _notEntered = true;
    }
}

contract Airdrop is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    mapping(address => bool) private Claimed;
    mapping(address => bool) private _isWhitelist;
    mapping(address => uint256) private _valDrop;

    IERC20 private _token;
    bool public airdropLive = false;

    event AirdropClaimed(address receiver, uint256 amount);
    event WhitelistSetted(address[] recipient, uint256[] amount);

    //Start Airdrop
    function startAirdrop(IERC20 tokenAddress) public onlyOwner {
        require(airdropLive == false, "Airdrop already started");
        _token = tokenAddress;
        airdropLive = true;
    }

    function setWhitelist(address[] calldata recipients, uint256[] calldata amount) external onlyOwner {
        for (uint i; i < recipients.length; i++) {
            require(recipients[i] != address(0));
            _valDrop[recipients[i]] = amount[i];
        }
        emit WhitelistSetted(recipients, amount);
    }

    function claimTokens() public nonReentrant {
        require(airdropLive == true, "Airdrop not started yet");
        require(Claimed[msg.sender] == false, "Airdrop already claimed!");
        if (_token.balanceOf(address(this)) == 0) {
            airdropLive = false;
            return;
        }
        Claimed[msg.sender] = true;
        uint256 amount = _valDrop[msg.sender].mul(10 ** 9);
        _token.transfer(msg.sender, amount);
        emit AirdropClaimed(msg.sender, amount);
    }

    function withdraw() external onlyOwner {
        require(address(this).balance > 0, "Contract has no money");
        address payable wallet = payable(msg.sender);
        wallet.transfer(address(this).balance);
    }

    function takeTokens(IERC20 tokenAddress) public onlyOwner {
        IERC20 tokenBEP = tokenAddress;
        uint256 tokenAmt = tokenBEP.balanceOf(address(this));
        require(tokenAmt > 0, "BEP-20 balance is 0");
        address payable wallet = payable(msg.sender);
        tokenBEP.transfer(wallet, tokenAmt);
    }
}
