// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract InvestorsManager {
    //INVESTORS DATA

    struct Investor {
        address investorAddress; //Investor address
        uint256 investment; //Total investor investment on miner (real BNB, presales/airdrops not taken into account)
        uint256 withdrawal; //Total investor withdraw BNB from the miner
        uint256 hiredMachines; //Total hired machines (miners)
        uint256 claimedGreens; //Total greens claimed (produced by machines)
        uint256 lastHire; //Last time you hired machines
        uint256 sellsTimestamp; //Last time you sold your greens
        uint256 nSells; //Number of sells you did
        uint256 referralGreens; //Number of greens you got from people that used your referral address
        address referral; //Referral address you used for joining the miner
        uint256 lastSellAmount; //Last sell amount
        uint256 customSellTaxes; //Custom tax set by admin
        uint256 referralUses; //Number of addresses that used his referral address
    }

    uint64 private _nInvestors = 0;
    uint64 private _totalReferralsUses = 0;
    uint256 private _totalReferralsGreens = 0;

    mapping(address => Investor) private _investors; //Investor data mapped by address
    mapping(uint64 => address) private _investorsAddresses; //Investors addresses mapped by index

    function getNumberInvestors() public view returns (uint64 nInvestor) {
        return _nInvestors;
    }

    function getTotalReferralsUses() public view returns (uint64 totalReferralsUse) {
        return _totalReferralsUses;
    }

    function getTotalReferralsGreens() public view returns (uint256 totalReferralsGreen) {
        return _totalReferralsGreens;
    }

    function getInvestorData(uint64 investorIndex) public view returns (Investor memory investorData) {
        return _investors[_investorsAddresses[investorIndex]];
    }

    function getInvestorData(address addr) public view returns (Investor memory investorData) {
        return _investors[addr];
    }

    function getInvestorMachines(address addr) public view returns (uint256 hiredMachines) {
        return _investors[addr].hiredMachines;
    }

    function getReferralData(address addr) public view returns (Investor memory referral) {
        return _investors[_investors[addr].referral];
    }

    function getReferralUses(address addr) public view returns (uint256 referralUses) {
        return _investors[addr].referralUses;
    }

    function _initializeInvestor(address adr) internal {
        if (_investors[adr].investorAddress != adr) {
            _investorsAddresses[_nInvestors] = adr;
            _investors[adr].investorAddress = adr;
            _investors[adr].sellsTimestamp = block.timestamp;
            _nInvestors++;
        }
    }

    function _setInvestorAddress(address addr) internal {
        _investors[addr].investorAddress = addr;
    }

    function _addInvestorInvestment(address addr, uint256 investment) internal {
        _investors[addr].investment += investment;
    }

    function _addInvestorWithdrawal(address addr, uint256 withdrawal) internal {
        _investors[addr].withdrawal += withdrawal;
    }

    function _setInvestorHiredMachines(address addr, uint256 hiredMachines) internal {
        _investors[addr].hiredMachines = hiredMachines;
    }

    function _setInvestorClaimedGreens(address addr, uint256 claimedGreens) internal {
        _investors[addr].claimedGreens = claimedGreens;
    }

    function _setInvestorGreensByReferral(address addr, uint256 greens) internal {
        if (addr != address(0)) {
            _totalReferralsGreens += greens;
            _totalReferralsGreens -= _investors[addr].referralGreens;
        }
        _investors[addr].referralGreens = greens;
    }

    function _setInvestorLastHire(address addr, uint256 lastHire) internal {
        _investors[addr].lastHire = lastHire;
    }

    function _setInvestorSellsTimestamp(address addr, uint256 sellsTimestamp) internal {
        _investors[addr].sellsTimestamp = sellsTimestamp;
    }

    function _setInvestorNsells(address addr, uint256 nSells) internal {
        _investors[addr].nSells = nSells;
    }

    function _setInvestorReferral(address addr, address referral) internal {
        _investors[addr].referral = referral;
        _investors[referral].referralUses++;
        _totalReferralsUses++;
    }

    function _setInvestorLastSell(address addr, uint256 amount) internal {
        _investors[addr].lastSellAmount = amount;
    }

    function _setInvestorCustomSellTaxes(address addr, uint256 customTax) internal {
        _investors[addr].customSellTaxes = customTax;
    }

    function _increaseReferralUses(address addr) internal {
        _investors[addr].referralUses++;
    }
}
