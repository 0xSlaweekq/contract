// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '../../libs/SafeMathInt.sol';
import '../../libs/SafeMathUint.sol';

interface IForceNFT {
    function getNFTRarity(uint256 tokenID) external view returns (uint8);

    function getNFTGen(uint256 tokenID) external view returns (uint8);

    function getNFTMetadata(uint256 tokenID) external view returns (uint8, uint8);

    function retrieveStolenNFTs() external returns (bool, uint256[] memory);
}

contract Staking is Ownable, IERC721Receiver {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    IForceNFT nftContract;
    IERC20 token;
    IERC20 stableCoin;
    address private marketing;

    uint256 private totalFarmed;

    struct UserInfo {
        uint256[] stakedSoldiers;
        uint256[] stakedOfficers;
        uint256[] stakedGenerals;
        uint256 numberOfSteals; // resets after block.timestamp > lastSteal + 24h
        uint256 lastSteal; // timestamp
    }

    struct NFTInfo {
        address owner;
        uint8 nftType;
        uint256 depositTime;
        uint256 lastHarvest;
        uint256 amountStolen;
        uint256 numberOfSteals;
        uint256 lastSteal;
    }

    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => NFTInfo) public nftInfo;

    uint256[] private stakedSoldiers;
    uint256[] private stakedOfficers; // array of staked officers TokenIDs
    uint256[] private stakedGenerals;

    uint256 private soldierReward = 1000 * 10 ** 18;
    uint256 private generalReward = 5000 * 10 ** 18;
    uint256 private stealPrice = 5 * 10 ** 18;
    uint256 private DAY = 60 * 60 * 24;

    uint256 private farmStartDate;

    constructor(address _token, address _nftContract, address _stableCoin, address _marketing) {
        nftContract = IForceNFT(_nftContract);
        token = IERC20(_token);
        stableCoin = IERC20(_stableCoin);
        marketing = _marketing;
    }

    receive() external payable {
        revert();
    }

    function getNFTpending(uint256 tokenId) external view returns (uint256) {
        NFTInfo storage nft = nftInfo[tokenId];
        if (nft.nftType == 0) {
            return _pendingSoldiersReward(tokenId);
        } else if (nft.nftType == 1) {
            return _pendingOfficersReward(tokenId);
        } else if (nft.nftType == 2) {
            return _pendingGeneralsReward(tokenId);
        } else {
            return 0;
        }
    }

    function startFarming(uint256 _startDate) external onlyOwner {
        if (_startDate != 0) {
            farmStartDate = _startDate;
        } else {
            farmStartDate = block.timestamp;
        }
    }

    function getNumOfStakedSoldiers() public view returns (uint256) {
        return stakedSoldiers.length;
    }

    function getNumOfStakedOfficers() public view returns (uint256) {
        return stakedOfficers.length;
    }

    function getNumOfStakedGenerals() public view returns (uint256) {
        return stakedGenerals.length;
    }

    function getTotalFarmed() public view returns (uint256) {
        return totalFarmed;
    }

    function stake(uint256 tokenId) external {
        _retrieveStolenNFTs();
        _stake(tokenId);
    }

    function stakeMultiple(uint256[] calldata tokenIds) external {
        _retrieveStolenNFTs();
        for (uint256 i; i < tokenIds.length; i++) {
            _stake(tokenIds[i]);
        }
    }

    function getStakedTokens(address owner) external view returns (uint256[] memory) {
        UserInfo storage user = userInfo[owner];
        uint256 length = user.stakedSoldiers.length + user.stakedOfficers.length + user.stakedGenerals.length;
        uint256[] memory tokenIds = new uint256[](length);
        uint256 counter;
        for (uint256 i; i < user.stakedSoldiers.length; i++) {
            tokenIds[counter] = user.stakedSoldiers[i];
            counter++;
        }
        for (uint256 i; i < user.stakedOfficers.length; i++) {
            tokenIds[counter] = user.stakedOfficers[i];
            counter++;
        }
        for (uint256 i; i < user.stakedGenerals.length; i++) {
            tokenIds[counter] = user.stakedGenerals[i];
            counter++;
        }
        return (tokenIds);
    }

    function unstake(uint256 tokenId) external {
        _retrieveStolenNFTs();
        _unstake(tokenId);
    }

    function unstakeMultiple(uint256[] calldata tokenIds) external {
        _retrieveStolenNFTs();
        for (uint256 i; i < tokenIds.length; i++) {
            _unstake(tokenIds[i]);
        }
    }

    function harvest(uint256 tokenId) external {
        _retrieveStolenNFTs();
        _harvestNormal(tokenId);
    }

    function harvestAll() external {
        _retrieveStolenNFTs();
        UserInfo storage user = userInfo[_msgSender()];
        for (uint256 i; i < user.stakedSoldiers.length; i++) {
            _harvestNormal(user.stakedSoldiers[i]);
        }
        for (uint256 i; i < user.stakedOfficers.length; i++) {
            _harvestNormal(user.stakedOfficers[i]);
        }
        for (uint256 i; i < user.stakedGenerals.length; i++) {
            _harvestNormal(user.stakedGenerals[i]);
        }
    }

    function pendingReward(address _address) external view returns (uint256) {
        return _pendingReward(_address);
    }

    function stealReward(uint256 tokenId) external {
        UserInfo storage user = userInfo[_msgSender()];
        NFTInfo storage nft = nftInfo[tokenId];
        require(nft.nftType == 1, 'Function is only for staked Officers');
        uint256 price;
        if (block.timestamp < nft.lastSteal + DAY) {
            nft.numberOfSteals += 1;
            price = nft.numberOfSteals * stealPrice;
        } else {
            nft.numberOfSteals = 1;
            price = stealPrice;
        }
        stableCoin.safeTransferFrom(_msgSender(), marketing, price);
        nft.lastSteal = block.timestamp;
        _stealReward(user);
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

        (uint8 nftType, ) = nftContract.getNFTMetadata(tokenId);
        IERC721(address(nftContract)).safeTransferFrom(_msgSender(), address(this), tokenId);
        if (nftType == 0) {
            user.stakedSoldiers.push(tokenId);
            stakedSoldiers.push(tokenId);
        } else if (nftType == 1) {
            user.stakedOfficers.push(tokenId);
            stakedOfficers.push(tokenId);
            _add(tokenId);
            nft.numberOfSteals = 0;
            nft.lastSteal = 0;
        } else if (nftType == 2) {
            user.stakedGenerals.push(tokenId);
            stakedGenerals.push(tokenId);
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
            require(block.timestamp >= nft.depositTime + 2 * DAY, '2 days have not passed');
            for (uint256 i; i < user.stakedSoldiers.length; i++) {
                if (user.stakedSoldiers[i] == tokenId) {
                    for (uint256 x = i; x < user.stakedSoldiers.length - 1; x++) {
                        user.stakedSoldiers[x] = user.stakedSoldiers[x + 1];
                    }
                    user.stakedSoldiers.pop();
                    found = true;
                }
            }
            for (uint256 i; i < stakedSoldiers.length; i++) {
                if (stakedSoldiers[i] == tokenId) {
                    for (uint256 x = i; x < stakedSoldiers.length - 1; x++) {
                        stakedSoldiers[x] = stakedSoldiers[x + 1];
                    }
                    stakedSoldiers.pop();
                }
            }
            nft.lastSteal = 0;
            nft.numberOfSteals = 0;
        } else if (nft.nftType == 1) {
            for (uint256 i; i < user.stakedOfficers.length; i++) {
                if (user.stakedOfficers[i] == tokenId) {
                    for (uint256 x = i; x < user.stakedOfficers.length - 1; x++) {
                        user.stakedOfficers[x] = user.stakedOfficers[x + 1];
                    }
                    user.stakedOfficers.pop();
                    found = true;
                }
            }
            for (uint256 i; i < stakedOfficers.length; i++) {
                if (stakedOfficers[i] == tokenId) {
                    for (uint256 x = i; x < stakedOfficers.length - 1; x++) {
                        stakedOfficers[x] = stakedOfficers[x + 1];
                    }
                    stakedOfficers.pop();
                }
            }
            _remove(tokenId);
        } else if (nft.nftType == 2) {
            for (uint256 i; i < user.stakedGenerals.length; i++) {
                if (user.stakedGenerals[i] == tokenId) {
                    for (uint256 x = i; x < user.stakedGenerals.length - 1; x++) {
                        user.stakedGenerals[x] = user.stakedGenerals[x + 1];
                    }
                    user.stakedGenerals.pop();
                    found = true;
                }
            }
            for (uint256 i; i < stakedGenerals.length; i++) {
                if (stakedGenerals[i] == tokenId) {
                    for (uint256 x = i; x < stakedGenerals.length - 1; x++) {
                        stakedGenerals[x] = stakedGenerals[x + 1];
                    }
                    stakedGenerals.pop();
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
                pendingReward_ = (timeDiff * soldierReward) / DAY - nft.amountStolen;
                if (stakedOfficers.length > 0) {
                    uint256 tax = (pendingReward_ * 2) / 10;
                    pendingReward_ -= tax;
                    distributeDividends(tax);
                }
            } else if (nft.nftType == 1) {
                withdrawDividend(tokenId);
            } else if (nft.nftType == 2) {
                pendingReward_ = (timeDiff * generalReward) / DAY;
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
                pendingReward_ = (timeDiff * soldierReward) / DAY - nft.amountStolen;
                if (stakedOfficers.length > 0) {
                    uint256 _probability = uint256(keccak256(abi.encodePacked(blockhash(block.number), tx.origin, block.timestamp))) %
                        100000;

                    if (_probability < 35000) {
                        uint256 tax = (pendingReward_ * 5) / 10;
                        pendingReward_ -= tax;
                        distributeDividends(tax);
                    }
                }
            } else if (nft.nftType == 1) {
                withdrawDividend(tokenId);
            } else if (nft.nftType == 2) {
                pendingReward_ = (timeDiff * generalReward) / DAY;
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
        if (user.stakedSoldiers.length > 0) {
            for (uint256 i; i < user.stakedSoldiers.length; i++) {
                pendingReward_ += _pendingSoldiersReward(user.stakedSoldiers[i]);
            }
        }
        if (user.stakedOfficers.length > 0) {
            for (uint256 i; i < user.stakedOfficers.length; i++) {
                pendingReward_ += _pendingOfficersReward(user.stakedOfficers[i]);
            }
        }
        if (user.stakedGenerals.length > 0) {
            for (uint256 i; i < user.stakedGenerals.length; i++) {
                pendingReward_ += _pendingGeneralsReward(user.stakedGenerals[i]);
            }
        }
    }

    function _pendingSoldiersReward(uint256 tokenId) internal view returns (uint256) {
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
            return (timeDiff * soldierReward) / DAY - nft.amountStolen;
        } else {
            return 0;
        }
    }

    function _pendingOfficersReward(uint256 tokenId) internal view returns (uint256) {
        return dividendOf(tokenId);
    }

    function _pendingGeneralsReward(uint256 tokenId) internal view returns (uint256) {
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
            return (timeDiff * generalReward) / DAY;
        } else {
            return 0;
        }
    }

    function _retrieveStolenNFTs() internal {
        if (stakedOfficers.length > 0) {
            (bool returned, uint256[] memory _stolenNFTs) = nftContract.retrieveStolenNFTs();
            if (returned) {
                for (uint256 i; i < _stolenNFTs.length; i++) {
                    uint256 _luckyWinner = uint256(keccak256(abi.encodePacked(blockhash(block.number), tx.origin, block.timestamp, i))) %
                        stakedOfficers.length;
                    uint256 winId = stakedOfficers[_luckyWinner];
                    address winner = nftInfo[winId].owner;
                    IERC721(address(nftContract)).safeTransferFrom(address(this), winner, _stolenNFTs[i]);
                }
            }
        }
    }

    function _stealReward(UserInfo storage user) internal {
        uint256 _randomSoldier = uint256(keccak256(abi.encodePacked(blockhash(block.number), tx.origin, block.timestamp + 20))) %
            stakedSoldiers.length;

        uint256 tokenId = stakedSoldiers[_randomSoldier];
        uint256 stolenReward;
        if (user.stakedGenerals.length > 0) {
            stolenReward = (_pendingSoldiersReward(tokenId) * 5) / 10;
        } else {
            stolenReward = (_pendingSoldiersReward(tokenId) * 3) / 10;
        }
        nftInfo[tokenId].amountStolen += stolenReward;
        totalFarmed += stolenReward;
        token.safeTransfer(_msgSender(), stolenReward);
    }

    /// @dev Officers Staking

    uint256 internal constant magnitude = 2 ** 128;

    uint256 internal magnifiedDividendPerShare;

    mapping(uint256 => int256) internal magnifiedDividendCorrections;
    mapping(uint256 => uint256) internal withdrawnDividends;

    function distributeDividends(uint256 amount) internal {
        require(stakedOfficers.length > 0);

        magnifiedDividendPerShare = magnifiedDividendPerShare.add((amount).mul(magnitude) / stakedOfficers.length);
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
        return magnifiedDividendPerShare.toInt256Safe().add(magnifiedDividendCorrections[tokenId]).toUint256Safe() / magnitude;
    }

    function _add(uint256 tokenId) internal {
        magnifiedDividendCorrections[tokenId] = magnifiedDividendCorrections[tokenId].sub((magnifiedDividendPerShare).toInt256Safe());
    }

    function _remove(uint256 tokenId) internal {
        magnifiedDividendCorrections[tokenId] = magnifiedDividendCorrections[tokenId].add((magnifiedDividendPerShare).toInt256Safe());
    }

    event Received();

    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) external override returns (bytes4) {
        _operator;
        _from;
        _tokenId;
        _data;
        emit Received();
        return 0x150b7a02;
    }
}
