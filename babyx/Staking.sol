// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '../libs/SafeMathInt.sol';
import '../libs/SafeMathUint.sol';

interface IMint {
    function getNFTRarity(uint256 tokenID) external view returns (uint8);

    function retrieveStolenNFTs() external returns (bool, uint256[] memory);
}

contract Staking is Ownable, IERC721Receiver {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    IMint nftContract;
    IERC20 token;

    uint256 private totalFarmed;

    struct UserInfo {
        uint256[] stakedBronze;
        uint256[] stakedSilver;
        uint256[] stakedGold;
        uint256 numberOfSteals; // resets after block.timestamp > lastSteal + 24h
        uint256 lastSteal; // timestamp
    }

    struct NFTInfo {
        address owner;
        uint8 nftType;
        uint256 depositTime;
        uint256 lastHarvest;
        uint256 amountStolen;
    }

    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => NFTInfo) public nftInfo;

    uint256[] private stakedBronze;
    uint256[] private stakedSilver; // array of staked Silver TokenIDs
    uint256[] private stakedGold;

    uint256 private bronzeReward = 14 * 10 ** 18;
    uint256 private goldReward = 38 * 10 ** 18;

    uint256 public grabXPrice = 5 * 10 ** 16;
    uint256 private grabXChangeStartTime;
    uint256 private grabXChangePriceTimeX;

    uint256 private DAY = 60 * 60 * 24;

    bool private farmStarted = false;
    uint256 private farmStartDate;

    constructor(address _token, address _nftContract) {
        nftContract = IMint(_nftContract);
        token = IERC20(_token);
    }

    receive() external payable {
        revert();
    }

    function getCurrentGrabXPrice() public view returns (uint256) {
        if (block.timestamp <= grabXChangeStartTime + 3600) return grabXChangePriceTimeX;
        else return grabXPrice;
    }

    function getNFTpending(uint256 tokenId) external view returns (uint256) {
        NFTInfo storage nft = nftInfo[tokenId];
        if (nft.nftType == 0) {
            return _pendingBronzeReward(tokenId);
        } else if (nft.nftType == 1) {
            return _pendingSilverReward(tokenId);
        } else if (nft.nftType == 2) {
            return _pendingGoldReward(tokenId);
        } else {
            return 0;
        }
    }

    function startFarming(uint256 _startDate) external {
        require(_msgSender() == owner() || _msgSender() == address(nftContract), 'Caller is not authorised');
        if (_msgSender() == address(nftContract)) {
            if (farmStartDate == 0) {
                farmStartDate = _startDate;
            }
        } else {
            if (_startDate != 0) {
                farmStartDate = _startDate;
            } else {
                farmStartDate = block.timestamp;
            }
        }
    }

    function getNumOfStakedBronze() public view returns (uint256) {
        return stakedBronze.length;
    }

    function getNumOfStakedSilver() public view returns (uint256) {
        return stakedSilver.length;
    }

    function getNumOfStakedGold() public view returns (uint256) {
        return stakedGold.length;
    }

    function getTotalFarmed() public view returns (uint256) {
        return totalFarmed;
    }

    function stakeMultiple(uint256[] calldata tokenIds) external {
        _retrieveStolenNFTs();
        for (uint256 i; i < tokenIds.length; i++) {
            _stake(tokenIds[i]);
        }
    }

    function getStakedTokens(address owner) external view returns (uint256[] memory) {
        UserInfo storage user = userInfo[owner];
        uint256 length = user.stakedBronze.length + user.stakedSilver.length + user.stakedGold.length;
        uint256[] memory tokenIds = new uint256[](length);
        uint256 counter;
        for (uint256 i; i < user.stakedBronze.length; i++) {
            tokenIds[counter] = user.stakedBronze[i];
            counter++;
        }
        for (uint256 i; i < user.stakedSilver.length; i++) {
            tokenIds[counter] = user.stakedSilver[i];
            counter++;
        }
        for (uint256 i; i < user.stakedGold.length; i++) {
            tokenIds[counter] = user.stakedGold[i];
            counter++;
        }
        return (tokenIds);
    }

    function unstakeMultiple(uint256[] calldata tokenIds) external {
        _retrieveStolenNFTs();
        for (uint256 i; i < tokenIds.length; i++) {
            _unstake(tokenIds[i]);
        }
    }

    function harvestAll() external {
        _retrieveStolenNFTs();
        UserInfo storage user = userInfo[_msgSender()];
        for (uint256 i; i < user.stakedBronze.length; i++) {
            _harvestNormal(user.stakedBronze[i]);
        }
        for (uint256 i; i < user.stakedSilver.length; i++) {
            _harvestNormal(user.stakedSilver[i]);
        }
        for (uint256 i; i < user.stakedGold.length; i++) {
            _harvestNormal(user.stakedGold[i]);
        }
    }

    function harvestBronze() external {
        _retrieveStolenNFTs();
        UserInfo storage user = userInfo[_msgSender()];
        for (uint256 i; i < user.stakedBronze.length; i++) {
            _harvestNormal(user.stakedBronze[i]);
        }
    }

    function harvestSilver() external {
        _retrieveStolenNFTs();
        UserInfo storage user = userInfo[_msgSender()];
        for (uint256 i; i < user.stakedSilver.length; i++) {
            _harvestNormal(user.stakedSilver[i]);
        }
    }

    function harvestGold() external {
        _retrieveStolenNFTs();
        UserInfo storage user = userInfo[_msgSender()];
        for (uint256 i; i < user.stakedGold.length; i++) {
            _harvestNormal(user.stakedGold[i]);
        }
    }

    function pendingReward(address _address) external view returns (uint256) {
        return _pendingReward(_address);
    }

    function changeGrabXPrice(uint256 newPrice) external onlyOwner {
        grabXPrice = newPrice * 10 ** 16;
    }

    function changeGrabXPriceTimeX(uint256 newPrice, uint256 startTime) external onlyOwner {
        if (startTime == 0) grabXChangePriceTimeX = block.timestamp;
        grabXChangePriceTimeX = newPrice * 10 ** 16;
        grabXChangePriceTimeX = startTime;
    }

    // price in native or tokens
    function stealReward(uint256 tokenId) external payable {
        UserInfo storage user = userInfo[_msgSender()];
        NFTInfo storage nft = nftInfo[tokenId];
        require(nft.nftType == 1, 'Function is only for staked Silver');
        uint256 price = getCurrentGrabXPrice();
        require(msg.value >= price, 'Not enough payed');
        _stealReward(user);
        payable(owner()).transfer(msg.value);
    }

    function retrieveFunds() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function withdrawAnyToken(IERC20 asset) external onlyOwner {
        asset.safeTransfer(owner(), asset.balanceOf(address(this)));
    }

    /// @dev Internal Functions

    function _stake(uint256 tokenId) internal {
        UserInfo storage user = userInfo[_msgSender()];
        NFTInfo storage nft = nftInfo[tokenId];

        uint8 nftType = nftContract.getNFTRarity(tokenId);
        IERC721(address(nftContract)).safeTransferFrom(_msgSender(), address(this), tokenId);
        if (nftType == 0) {
            user.stakedBronze.push(tokenId);
            stakedBronze.push(tokenId);
        } else if (nftType == 1) {
            user.stakedSilver.push(tokenId);
            stakedSilver.push(tokenId);
            _add(tokenId);
        } else if (nftType == 2) {
            user.stakedGold.push(tokenId);
            stakedGold.push(tokenId);
        } else {
            revert('Token metadata is unreachable');
        }
        nft.owner = _msgSender();
        nft.nftType = nftType;
        nft.depositTime = block.timestamp;
        nft.lastHarvest = block.timestamp;
    }

    function _unstake(uint256 tokenId) internal {
        _harvestUnstake(tokenId);
        UserInfo storage user = userInfo[_msgSender()];
        NFTInfo storage nft = nftInfo[tokenId];
        require(nft.owner == _msgSender(), 'Caller is not the owner');
        bool found;
        if (nft.nftType == 0) {
            for (uint256 i; i < user.stakedBronze.length; i++) {
                if (user.stakedBronze[i] == tokenId) {
                    for (uint256 x = i; x < user.stakedBronze.length - 1; x++) {
                        user.stakedBronze[x] = user.stakedBronze[x + 1];
                    }
                    user.stakedBronze.pop();
                    found = true;
                }
            }
            for (uint256 i; i < stakedBronze.length; i++) {
                if (stakedBronze[i] == tokenId) {
                    for (uint256 x = i; x < stakedBronze.length - 1; x++) {
                        stakedBronze[x] = stakedBronze[x + 1];
                    }
                    stakedBronze.pop();
                }
            }
        } else if (nft.nftType == 1) {
            for (uint256 i; i < user.stakedSilver.length; i++) {
                if (user.stakedSilver[i] == tokenId) {
                    for (uint256 x = i; x < user.stakedSilver.length - 1; x++) {
                        user.stakedSilver[x] = user.stakedSilver[x + 1];
                    }
                    user.stakedSilver.pop();
                    found = true;
                }
            }
            for (uint256 i; i < stakedSilver.length; i++) {
                if (stakedSilver[i] == tokenId) {
                    for (uint256 x = i; x < stakedSilver.length - 1; x++) {
                        stakedSilver[x] = stakedSilver[x + 1];
                    }
                    stakedSilver.pop();
                }
            }
            _remove(tokenId);
        } else if (nft.nftType == 2) {
            for (uint256 i; i < user.stakedGold.length; i++) {
                if (user.stakedGold[i] == tokenId) {
                    for (uint256 x = i; x < user.stakedGold.length - 1; x++) {
                        user.stakedGold[x] = user.stakedGold[x + 1];
                    }
                    user.stakedGold.pop();
                    found = true;
                }
            }
            for (uint256 i; i < stakedGold.length; i++) {
                if (stakedGold[i] == tokenId) {
                    for (uint256 x = i; x < stakedGold.length - 1; x++) {
                        stakedGold[x] = stakedGold[x + 1];
                    }
                    stakedGold.pop();
                }
            }
        } else {
            revert('Token metadata is unreachable');
        }

        nft.owner = address(0);
        require(found, 'Error');
        IERC721(address(nftContract)).safeTransferFrom(address(this), _msgSender(), tokenId);
    }

    function _harvestNormal(uint256 tokenId) internal {
        NFTInfo storage nft = nftInfo[tokenId];
        require(nft.owner == _msgSender(), 'Caller is not token staker');
        if (farmStartDate != 0 && farmStartDate <= block.timestamp) {
            uint256 pendingReward_;
            uint256 timeDiff;
            if (farmStartDate > nft.lastHarvest) {
                timeDiff = block.timestamp - farmStartDate;
            } else {
                timeDiff = block.timestamp - nft.lastHarvest;
            }
            if (nft.nftType == 0) {
                pendingReward_ = _pendingBronzeReward(tokenId);
                if (
                    stakedSilver.length > 0 &&
                    userInfo[_msgSender()].stakedGold.length == 0 &&
                    pendingReward_ < 60 * 10 ** 18
                ) {
                    uint256 tax = (pendingReward_ * 2) / 10;
                    pendingReward_ -= tax;
                    distributeDividends(tax);
                }
            } else if (nft.nftType == 1) {
                withdrawDividend(tokenId);
            } else if (nft.nftType == 2) {
                pendingReward_ = (timeDiff * goldReward) / DAY;
            } else {
                revert('Token metadata is unreachable');
            }
            nft.lastHarvest = block.timestamp;
            nft.amountStolen = 0;
            if (pendingReward_ > 0) {
                totalFarmed += pendingReward_;
                token.safeTransfer(_msgSender(), pendingReward_);
            }
        }
    }

    function _harvestUnstake(uint256 tokenId) internal {
        NFTInfo storage nft = nftInfo[tokenId];
        require(nft.owner == _msgSender(), 'Caller is not token staker');
        if (farmStartDate != 0 && farmStartDate <= block.timestamp) {
            uint256 pendingReward_;
            uint256 timeDiff;
            if (farmStartDate > nft.lastHarvest) {
                timeDiff = block.timestamp - farmStartDate;
            } else {
                timeDiff = block.timestamp - nft.lastHarvest;
            }
            if (nft.nftType == 0) {
                pendingReward_ = _pendingBronzeReward(tokenId);
                require(pendingReward_ >= 60 * 10 ** 18, '60 tokens were not farmed yet');
                if (stakedSilver.length > 0) {
                    uint256 _probability = uint256(
                        keccak256(abi.encodePacked(blockhash(block.number), tx.origin, block.timestamp))
                    ) % 100000;

                    if (_probability < 35000) {
                        uint256 tax = (pendingReward_ * 5) / 10;
                        pendingReward_ -= tax;
                        distributeDividends(tax);
                    }
                }
            } else if (nft.nftType == 1) {
                withdrawDividend(tokenId);
            } else if (nft.nftType == 2) {
                pendingReward_ = (timeDiff * goldReward) / DAY;
            }
            nft.lastHarvest = block.timestamp;
            nft.amountStolen = 0;
            if (pendingReward_ > 0) {
                totalFarmed += pendingReward_;
                token.safeTransfer(nftInfo[tokenId].owner, pendingReward_);
            }
        }
    }

    function _pendingReward(address _address) internal view returns (uint256 pendingReward_) {
        UserInfo storage user = userInfo[_address];
        if (user.stakedBronze.length > 0) {
            for (uint256 i; i < user.stakedBronze.length; i++) {
                pendingReward_ += _pendingBronzeReward(user.stakedBronze[i]);
            }
        }
        if (user.stakedSilver.length > 0) {
            for (uint256 i; i < user.stakedSilver.length; i++) {
                pendingReward_ += _pendingSilverReward(user.stakedSilver[i]);
            }
        }
        if (user.stakedGold.length > 0) {
            for (uint256 i; i < user.stakedGold.length; i++) {
                pendingReward_ += _pendingGoldReward(user.stakedGold[i]);
            }
        }
    }

    function _pendingBronzeReward(uint256 tokenId) internal view returns (uint256) {
        if (farmStartDate == 0 || farmStartDate > block.timestamp) {
            return 0;
        }
        NFTInfo storage nft = nftInfo[tokenId];
        if (nft.owner != address(0)) {
            uint256 timeDiff;
            if (farmStartDate > nft.lastHarvest) {
                timeDiff = block.timestamp - farmStartDate;
            } else {
                timeDiff = block.timestamp - nft.lastHarvest;
            }
            return (timeDiff * bronzeReward) / DAY - nft.amountStolen;
        } else {
            return 0;
        }
    }

    function _pendingSilverReward(uint256 tokenId) internal view returns (uint256) {
        return dividendOf(tokenId);
    }

    function _pendingGoldReward(uint256 tokenId) internal view returns (uint256) {
        if (farmStartDate == 0 || farmStartDate > block.timestamp) {
            return 0;
        }
        NFTInfo storage nft = nftInfo[tokenId];
        if (nft.owner != address(0)) {
            uint256 timeDiff;
            if (farmStartDate > nft.lastHarvest) {
                timeDiff = block.timestamp - farmStartDate;
            } else {
                timeDiff = block.timestamp - nft.lastHarvest;
            }
            return (timeDiff * goldReward) / DAY;
        } else {
            return 0;
        }
    }

    function _retrieveStolenNFTs() internal {
        if (stakedSilver.length > 0) {
            (bool returned, uint256[] memory _stolenNFTs) = nftContract.retrieveStolenNFTs();
            if (returned) {
                for (uint256 i; i < _stolenNFTs.length; i++) {
                    uint256 _luckyWinner = uint256(
                        keccak256(abi.encodePacked(blockhash(block.number), tx.origin, block.timestamp, i))
                    ) % stakedSilver.length;
                    uint256 winId = stakedSilver[_luckyWinner];
                    address winner = nftInfo[winId].owner;
                    IERC721(address(nftContract)).safeTransferFrom(address(this), winner, _stolenNFTs[i]);
                }
            }
        }
    }

    function _stealReward(UserInfo storage user) internal {
        uint256 _randomBronze = uint256(
            keccak256(abi.encodePacked(blockhash(block.number), tx.origin, block.timestamp + 20))
        ) % stakedBronze.length;

        uint256 tokenId = stakedBronze[_randomBronze];
        address owner = nftInfo[tokenId].owner;
        uint256 totalStolenReward;
        for (uint256 i; i < userInfo[owner].stakedBronze.length; i++) {
            uint256 stolenReward;
            tokenId = userInfo[owner].stakedBronze[i];
            if (user.stakedGold.length > 0) {
                stolenReward = (_pendingBronzeReward(tokenId) * 30) / 100;
                totalStolenReward += stolenReward;
            } else {
                stolenReward = (_pendingBronzeReward(tokenId) * 15) / 100;
                totalStolenReward += stolenReward;
            }
            nftInfo[tokenId].amountStolen += stolenReward;
        }
        totalFarmed += totalStolenReward;
        token.safeTransfer(_msgSender(), totalStolenReward);
    }

    /// @dev Silver Staking

    uint256 internal constant magnitude = 2 ** 128;

    uint256 internal magnifiedDividendPerShare;

    mapping(uint256 => int256) internal magnifiedDividendCorrections;
    mapping(uint256 => uint256) internal withdrawnDividends;

    function distributeDividends(uint256 amount) internal {
        require(stakedSilver.length > 0);

        magnifiedDividendPerShare = magnifiedDividendPerShare.add((amount).mul(magnitude) / stakedSilver.length);
    }

    function withdrawDividend(uint256 tokenId) internal {
        require(nftInfo[tokenId].owner == _msgSender(), 'Caller is not the staker');
        uint256 _withdrawableDividend = withdrawableDividendOf(tokenId);
        if (_withdrawableDividend > 0) {
            withdrawnDividends[tokenId] = withdrawnDividends[tokenId].add(_withdrawableDividend);
            token.safeTransfer(_msgSender(), _withdrawableDividend);
        }
    }

    function dividendOf(uint256 tokenId) internal view returns (uint256) {
        return withdrawableDividendOf(tokenId);
    }

    function withdrawableDividendOf(uint256 tokenId) internal view returns (uint256) {
        return accumulativeDividendOf(tokenId).sub(withdrawnDividends[tokenId]);
    }

    function withdrawnDividendOf(uint256 tokenId) internal view returns (uint256) {
        return withdrawnDividends[tokenId];
    }

    function accumulativeDividendOf(uint256 tokenId) internal view returns (uint256) {
        return
            magnifiedDividendPerShare.toInt256Safe().add(magnifiedDividendCorrections[tokenId]).toUint256Safe() /
            magnitude;
    }

    function _add(uint256 tokenId) internal {
        magnifiedDividendCorrections[tokenId] = magnifiedDividendCorrections[tokenId].sub(
            (magnifiedDividendPerShare).toInt256Safe()
        );
    }

    function _remove(uint256 tokenId) internal {
        magnifiedDividendCorrections[tokenId] = magnifiedDividendCorrections[tokenId].add(
            (magnifiedDividendPerShare).toInt256Safe()
        );
    }

    event Received();

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        _operator;
        _from;
        _tokenId;
        _data;
        emit Received();
        return 0x150b7a02;
    }
}
