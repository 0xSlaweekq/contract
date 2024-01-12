// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../libs/SafeMathUint.sol";

contract DynamicWeightedLP {
    using SafeMath for uint256;
    using SafeMathUint for uint256;

    struct UserInfo {
        uint256 amountLP;
        uint256 weight;
        uint256 lastTotalWeight;
        uint256 availibleToClaim;
        uint256 lastTotalFarmed;
    }

    mapping(address => UserInfo) public userInfo;
    bool public started;

    address owner;

    uint256 public startTime;
    uint256 public totalLP;
    uint256 public totalWeight;
    uint256 public lastUpdateTime;
    uint256 public totalFarmed;
    uint256 public reinvestTime;

    event SendTransaction(uint256 typeF, UserInfo userInfo);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller not owner");
        _;
    }

    function sendTransaction(uint256 typeF, uint256 amountLP) public {
        // typeF 0-deposit, 1-withdraw, 2-reinvest
        address user = msg.sender;

        uint256 time = block.timestamp;
        uint256 curAmountLP = userInfo[user].amountLP;

        if (typeF == 0) {
            if (curAmountLP <= 0) {
                userInfo[user] = UserInfo(0, 0, 0, 0, 0);
            }
        }

        if (typeF == 1) {
            require(curAmountLP > 0, "You dont using this pool");
            require(curAmountLP >= amountLP, "Insufficient LP amount");
        }

        if (_updateInfo(user, typeF, curAmountLP, amountLP, time)) {
            emit SendTransaction(typeF, userInfo[user]);
        } else {
            revert("hz tut potom uzhe dumat");
        }
    }

    function _updateInfo(address user, uint256 typeF, uint256 curAmountLP, uint256 amountLP, uint256 time)
        internal
        returns (bool)
    {
        if (!started) {
            startTime = time;
            started = true;
        }

        uint256 dTime = time - lastUpdateTime;
        if (dTime != 0 && totalLP != 0) {
            totalWeight += dTime.div(totalLP);
            lastUpdateTime = time;
        }

        uint256 weight = userInfo[user].weight.add(curAmountLP.mul(totalWeight.sub(userInfo[user].lastTotalWeight)));

        if (typeF == 0) {
            curAmountLP += amountLP;
            totalLP += amountLP;
        }

        if (typeF == 1) {
            curAmountLP -= amountLP;
            totalLP -= amountLP;
        }

        if (totalFarmed != 0 && userInfo[user].lastTotalFarmed != totalFarmed) {
            uint256 dTimeAll = time - startTime;
            uint256 percent = weight / dTimeAll;
            userInfo[user] = UserInfo(curAmountLP, weight, totalWeight, percent * totalFarmed, totalFarmed);
        } else {
            userInfo[user] = UserInfo(curAmountLP, weight, totalWeight, 0, 0);
        }

        return true;
    }

    function getPercentForUser(address userAddr) external view returns (uint256) {
        UserInfo memory user = userInfo[userAddr];
        uint256 time = block.timestamp;
        uint256 dTimeAll = time - startTime;
        uint256 dTime = time - lastUpdateTime;
        uint256 totalWeights = totalWeight.add(dTime.div(totalLP));

        uint256 percent = user.weight.add(user.amountLP.mul(totalWeights.sub(user.lastTotalWeight))).div(dTimeAll);

        return percent;
    }

    function _getCurrentFarmed() internal view returns (uint256) {
        uint256 time = block.timestamp;
        uint256 dTime;
        if (reinvestTime != 0) dTime = time - reinvestTime;
        else dTime = time - startTime;
        return 100 * dTime;
    }

    function reinvest() external onlyOwner returns (bool) {
        (uint256 currentFarmed) = _getCurrentFarmed();
        totalLP += currentFarmed;
        totalFarmed += currentFarmed;
        currentFarmed = 0;
        reinvestTime = block.timestamp;
        return true;
    }
}
