// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;
// import '@openzeppelin/contracts/utils/Address.sol';
// import '@openzeppelin/contracts/utils/Counters.sol';
// import '@openzeppelin/contracts/utils/Strings.sol';
// import '@openzeppelin/contracts/utils/math/SafeMath.sol';
// import '@openzeppelin/contracts/access/Ownable.sol';
// import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
// import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
// import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';

// contract TokenMint is Ownable, ERC721URIStorage, ERC721Enumerable {
//   using SafeMath for uint256;
//   using Strings for uint256;
//   using Address for address;
//   using Counters for Counters.Counter;

//   struct TopHolder {
//     address holder;
//     uint256 balance;
//     uint256 withdrawAmount;
//     bool equalBalance;
//     bool paidOut;
//   }

//   uint256 public maxSupply;
//   uint256 public reservedSupply = 0;
//   uint256 public reservedMaxSupply;
//   uint256 public price;
//   uint256 public amountFunds;
//   uint256 public maxMintRequest;
//   uint256 public availableFunds;
//   uint256 public reflectionBalance;
//   uint256 public totalDividend;
//   uint256 public fees;
//   uint256 private _circulatingSupply;
//   string public baseTokenURI;

//   TopHolder public topHolder;

//   address[] public funds;
//   mapping(uint256 => uint256) public lastDividendAt;

//   mapping(address => bool) private whitelist;

//   bool public whitelistOnly;

//   event Mint(uint256 tokenId, address to);

//   function getReflectionBalance(uint256 _tokenId) public view returns (uint256) {
//     return totalDividend.sub(lastDividendAt[_tokenId]);
//   }

//   // function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
//   //   return super.supportsInterface(interfaceId);
//   // }


//   function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
//     return ERC721URIStorage.tokenURI(tokenId);
//   }

//   constructor(
//     string memory _name,
//     string memory _symbol,
//     uint256 _maxSupply,
//     uint256 _price, //*100
//     uint256 _reservedMaxSupply,
//     uint256 _maxMintRequest,
//     uint256 _withdrawValueTopHolder,
//     uint256 _fees,
//     string memory _baseTokenURI,
//     address[] memory _funds
//   ) ERC721(_name, _symbol) {
//     fees = _fees;
//     maxSupply = _maxSupply;
//     reservedMaxSupply = _reservedMaxSupply;
//     price = _price.mul(10 ** 16);
//     maxMintRequest = _maxMintRequest;
//     baseTokenURI = _baseTokenURI;
//     funds = _funds;
//     topHolder.withdrawAmount = _withdrawValueTopHolder.mul(10 ** 16);
//   }

//   receive() external payable {}

//   function claimRewards() external returns (bool) {
//     require(_msgSender() != owner(), 'Owner can not claim rewards');
//     uint256 count = balanceOf(_msgSender());
//     uint256 balance = 0;
//     for (uint256 i; i < count; i++) {
//       uint256 tokenId = tokenOfOwnerByIndex(_msgSender(), i);
//       if (tokenId >= reservedMaxSupply) balance = balance.add(getReflectionBalance(tokenId));

//       lastDividendAt[tokenId] = totalDividend;
//     }
//     payable(_msgSender()).transfer(balance);
//     return true;
//   }

//   function mint(uint256 _amount) external payable {
//     address owner = owner();
//     address sender = _msgSender();
//     require(_circulatingSupply + _amount <= 421, 'All tokens were minted');
//     require(!Address.isContract(sender), 'Sender is a contract');
//     require(_amount > 0, 'Requested mint amount must be greater than zero');
//     require(_circulatingSupply < maxSupply, 'Max mint supply reached');
//     require(_amount.add(_circulatingSupply) <= maxSupply, 'Requested mint amount overflows maximum mint supply');
//     if (sender != owner) {
//       require(reservedSupply == reservedMaxSupply, 'Sale can not start untill reserved supply has been minted');
//       require(msg.value >= _amount.mul(price), 'Insufficient value sent');
//       require(_amount <= maxMintRequest, 'Requested mint amount is bigger than max authorized mint request');
//     } else {
//       require(reservedSupply < reservedMaxSupply, 'Maximum reserved mint supply reached');
//       require(_amount.add(reservedSupply) <= reservedMaxSupply, 'Requested mint amount overflows reserved maximum mint supply');
//       reservedSupply = reservedSupply.add(_amount);
//     }
//     if (whitelistOnly) require(whitelist[_msgSender()], 'Address is not in whitelist');

//     uint256 localfees = 0;
//     for (uint256 i; i < _amount; i++) {
//       string memory newTokenURI = string(abi.encodePacked(baseTokenURI, Strings.toString(_circulatingSupply)));
//       _safeMint(sender, _circulatingSupply);
//       _setTokenURI(_circulatingSupply, newTokenURI);
//       if (sender != owner) {
//         lastDividendAt[_circulatingSupply] = totalDividend;
//         reflectDividend((price.div(1000)).mul(fees));
//         localfees = localfees.add((price.div(1000)).mul(fees));
//       } else {
//         lastDividendAt[_circulatingSupply] = 0;
//       }
//       emit Mint(_circulatingSupply, sender);
//       _circulatingSupply++;
//     }
//     availableFunds = availableFunds.add(msg.value.sub(localfees));
//     _setTopHolder(address(0), sender);
//   }

//   function setBaseTokenURI(string memory _baseURI) public onlyOwner returns (bool) {
//     require(_circulatingSupply == 0, 'Can not change URI once mint started');
//     baseTokenURI = _baseURI;
//     return true;
//   }

//   function withdrawFunds(uint256 _amount) external onlyOwner returns (bool) {
//     amountFunds = _amount.mul(10 ** 12);
//     require(amountFunds > 0, 'Available funds is zero');
//     require(availableFunds > 0, 'Available funds is zero');
//     require(amountFunds <= availableFunds, 'amountFunds better available');
//     uint256 shareFund = amountFunds.div(funds.length);
//     availableFunds = availableFunds.sub(amountFunds);
//     for (uint256 i; i < funds.length; i++) {
//       payable(funds[i]).transfer(shareFund);
//     }
//     return true;
//   }

//   function withdrawTopHolder() public returns (bool) {
//     require(_circulatingSupply >= maxSupply, 'Collection not purchased');
//     require(!topHolder.equalBalance, 'Top holder is not the only one');
//     require(!topHolder.paidOut, 'The reward has already been paid');
//     payable(topHolder.holder).transfer(topHolder.withdrawAmount);
//     topHolder.paidOut = true;
//     return true;
//   }

//   function reflectDividend(uint256 _amount) private {
//     reflectionBalance = reflectionBalance.add(_amount);
//     totalDividend = totalDividend.add(_amount.div(_circulatingSupply.sub(reservedMaxSupply).add(1)));
//   }

//   function _burn(uint256 tokenId) internal virtual override(ERC721, ERC721URIStorage) {
//     return ERC721URIStorage._burn(tokenId);
//   }

//   function _transfer(address from, address to, uint256 tokenId) internal override {
//     super._transfer(from, to, tokenId);
//     _setTopHolder(from, to);
//   }

//   function _setTopHolder(address from, address holder) private returns (bool) {
//     uint256 balanceHolder = balanceOf(holder);
//     if (from != address(0) && from == topHolder.holder) topHolder.balance = balanceOf(from);

//     if (balanceHolder > topHolder.balance) {
//       topHolder.holder = holder;
//       topHolder.balance = balanceHolder;
//       topHolder.equalBalance = false;
//     }
//     if (balanceHolder == topHolder.balance && holder != topHolder.holder) topHolder.equalBalance = true;

//     return true;
//   }

//   function getUserInfo() public view returns (uint256) {
//     uint256 count = balanceOf(_msgSender());
//     uint256 balance = 0;
//     for (uint256 i; i < count; i++) {
//       uint256 tokenId = tokenOfOwnerByIndex(_msgSender(), i);
//       if (tokenId >= reservedMaxSupply) balance = balance.add(getReflectionBalance(tokenId));
//     }
//     return balance;
//   }

//   function getUserNFTIds(address owner) public view returns (uint256[] memory) {
//     uint256[] memory NFTIDS = new uint256[](balanceOf(owner));
//     for (uint256 i; i < balanceOf(owner); i++) {
//       NFTIDS[i] = tokenOfOwnerByIndex(owner, i);
//     }
//     return NFTIDS;
//   }

//   function isInWhitelist(address _address) external view returns (bool) {
//     return whitelist[_address];
//   }

//   function setWhitelistStatus(bool value) external onlyOwner {
//     whitelistOnly = value;
//   }

//   function addToWhitelist(address _address) external onlyOwner {
//     _addToWhitelist(_address);
//   }

//   function addMultipleToWhitelist(address[] memory _addresses) external onlyOwner {
//     for (uint256 i; i < _addresses.length; i++) {
//       _addToWhitelist(_addresses[i]);
//     }
//   }

//   function _addToWhitelist(address _address) internal {
//     whitelist[_address] = true;
//   }

//   function cirulatingSupply() public view returns (uint256) {
//     return _circulatingSupply;
//   }

//   function Burn(uint256 amount) public onlyOwner {
//     _circulatingSupply += amount;
//   }
// }
