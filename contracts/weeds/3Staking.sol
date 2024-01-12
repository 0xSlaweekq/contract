// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '../../libs/SafeMathInt.sol';
import '../../libs/SafeMathUint.sol';

interface IWeedsLab {
  function getNFTMetadata(uint256 tokenID) external view returns (uint8, uint8);
}

contract Staking is Ownable, IERC721Receiver {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using SafeMathUint for uint256;
  using SafeMathInt for int256;

  IWeedsLab nftContract;
  IERC20 token;

  uint256 private totalFarmed;

  struct UserInfo {
    uint256[] stakedSols;
    uint256 numberOfTokens;
  }

  struct NFTInfo {
    address owner;
    uint8 nftType;
    uint256 depositTime;
    uint256 lastHarvest;
  }

  mapping(address => UserInfo) public userInfo;
  mapping(uint256 => NFTInfo) public nftInfo;

  uint256[] private stakedSols;

  uint256 private solReward = 5 * 10 ** 18;

  uint256 private DAY = 60 * 60 * 24;

  bool private farmStarted = false;
  uint256 private farmStartDate;

  constructor(address _token, address _nftContract) {
    nftContract = IWeedsLab(_nftContract);
    token = IERC20(_token);
  }

  receive() external payable {
    revert();
  }

  function getNFTpending(uint256 tokenId) external view returns (uint256) {
    NFTInfo storage nft = nftInfo[tokenId];
    if (nft.nftType == 0) return _pendingSolsReward(tokenId);
    else return 0;
  }

  function startFarming(uint256 _startDate) external {
    require(_msgSender() == owner() || _msgSender() == address(nftContract), 'Caller is not authorised');
    if (_msgSender() == address(nftContract)) {
      if (farmStartDate == 0) farmStartDate = _startDate;
    } else {
      if (_startDate != 0) farmStartDate = _startDate;
      else farmStartDate = block.timestamp;
    }
  }

  function getNumOfStakedSols() public view returns (uint256) {
    return stakedSols.length;
  }

  function getTotalFarmed() public view returns (uint256) {
    return totalFarmed;
  }

  function stake(uint256 tokenId) external {
    _stake(tokenId);
  }

  function stakeMultiple(uint256[] calldata tokenIds) external {
    for (uint256 i; i < tokenIds.length; i++) {
      _stake(tokenIds[i]);
    }
  }

  function getStakedTokens(address owner) external view returns (uint256[] memory) {
    UserInfo storage user = userInfo[owner];
    uint256 length = user.stakedSols.length;
    uint256[] memory tokenIds = new uint256[](length);
    uint256 counter;
    for (uint256 i; i < user.stakedSols.length; i++) {
      tokenIds[counter] = user.stakedSols[i];
      counter++;
    }
    return (tokenIds);
  }

  function unstake(uint256 tokenId) external {
    _unstake(tokenId);
  }

  function unstakeMultiple(uint256[] calldata tokenIds) external {
    for (uint256 i; i < tokenIds.length; i++) {
      _unstake(tokenIds[i]);
    }
  }

  function harvest(uint256 tokenId) external {
    _harvestNormal(tokenId);
  }

  function harvestAll() external {
    UserInfo storage user = userInfo[_msgSender()];
    for (uint256 i; i < user.stakedSols.length; i++) {
      _harvestNormal(user.stakedSols[i]);
    }
  }

  function pendingReward(address _address) external view returns (uint256) {
    return _pendingReward(_address);
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
      user.stakedSols.push(tokenId);
      stakedSols.push(tokenId);
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
      for (uint256 i; i < user.stakedSols.length; i++) {
        if (user.stakedSols[i] == tokenId) {
          for (uint256 x = i; x < user.stakedSols.length - 1; x++) {
            user.stakedSols[x] = user.stakedSols[x + 1];
          }
          user.stakedSols.pop();
          found = true;
        }
      }
      for (uint256 i; i < stakedSols.length; i++) {
        if (stakedSols[i] == tokenId) {
          for (uint256 x = i; x < stakedSols.length - 1; x++) {
            stakedSols[x] = stakedSols[x + 1];
          }
          stakedSols.pop();
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
      if (farmStartDate > nft.lastHarvest) timeDiff = block.timestamp - farmStartDate;
      else timeDiff = block.timestamp - nft.lastHarvest;

      if (nft.nftType == 0) pendingReward_ = _pendingSolsReward(tokenId);
      else revert('Token metadata is unreachable');

      nft.lastHarvest = block.timestamp;
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
      if (farmStartDate > nft.lastHarvest) timeDiff = block.timestamp - farmStartDate;
      else timeDiff = block.timestamp - nft.lastHarvest;

      if (nft.nftType == 0) pendingReward_ = _pendingSolsReward(tokenId);

      nft.lastHarvest = block.timestamp;
      if (pendingReward_ > 0) {
        totalFarmed += pendingReward_;
        token.safeTransfer(nftInfo[tokenId].owner, pendingReward_);
      }
    }
  }

  function _pendingReward(address _address) internal view returns (uint256 pendingReward_) {
    UserInfo storage user = userInfo[_address];
    if (user.stakedSols.length > 0)
      for (uint256 i; i < user.stakedSols.length; i++) {
        pendingReward_ += _pendingSolsReward(user.stakedSols[i]);
      }
  }

  function _pendingSolsReward(uint256 tokenId) internal view returns (uint256) {
    if (farmStartDate == 0 || farmStartDate > block.timestamp) return 0;

    NFTInfo storage nft = nftInfo[tokenId];
    if (nft.owner != address(0)) {
      uint256 timeDiff;
      if (farmStartDate > nft.lastHarvest) timeDiff = block.timestamp - farmStartDate;
      else timeDiff = block.timestamp - nft.lastHarvest;

      return (timeDiff * solReward) / DAY;
    } else {
      return 0;
    }
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
