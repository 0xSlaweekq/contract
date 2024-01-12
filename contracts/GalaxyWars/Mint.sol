// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/security/Pausable.sol';

interface IGalaxyWars {
  function getNFTRarity(uint256 tokenID) external view returns (uint8);
  function getNFTGen(uint256 tokenID) external view returns (uint8);
  function getNFTMetadata(uint256 tokenID) external view returns (uint8, uint8);
  function retrieveStolenNFTs() external returns (bool, uint256[] memory);
}

interface IStaking {
  function startFarming(uint256 _startDate) external;
}

contract GalaxyWars is ERC165, IERC721, IERC721Metadata, Ownable, Pausable {
  using Address for address;
  using Strings for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  // Mapping that stores all token ids of an owner (owner => tokenIds[])
  mapping(address => EnumerableSet.UintSet) internal ownerToTokens;

  struct PriceChange {
    uint256 startTime;
    uint256 newPrice;
  }

  address[] private claimWallets;
  mapping(address => uint256) private claimAmounts;

  mapping(uint8 => PriceChange) private priceChange;

  struct NFTMetadata {
    /**
        _nftType:
        0 - Soldier
        1 - Officer
        2 - General
         */
    uint8 _nftType;
    /**
        gen:
        Gen 0 - from 1 to 2500
        Gen 1 - from 2501 to 6000
        Gen 2 - from 6001 to 10000
         */
    uint8 gen;
  }

  uint256[] private mintedSoldiers;
  uint256[] private mintedOfficers;
  uint256[] private mintedGenerals;
  uint256[] private stolenNFTs;
  uint256[] private pendingStolenNFTs;

  // Token name
  string private _name = 'Galaxy Wars Game';

  // Token symbol
  string private _symbol = 'GalaxyWars';

  // Mapping from token ID to owner address
  mapping(uint256 => address) private _owners;

  // Mapping owner address to token count
  mapping(address => uint256) private _balances;

  // Mapping from token ID to approved address
  mapping(uint256 => address) private _tokenApprovals;

  // Mapping from owner to operator approvals
  mapping(address => mapping(address => bool)) private _operatorApprovals;

  uint256 private _totalSupply = 10000;
  uint256 private _totalOfficers = 950;
  uint256 private _totalGenerals = 50;
  uint256 private _enteredOfficers;
  uint256 private _enteredGenerals;
  uint256 private _circulatingSupply;

  uint256 private _startSteal;

  mapping(uint256 => NFTMetadata) private _nftMetadata;

  mapping(address => bool) private whitelist;

  mapping(address => uint256) public lists;
  mapping(address => uint256) public usedLists;
  bool public listEnabled = false;

  bool public whitelistOnly;

  address stakingContract;

  bool public _revealed;

  string private baseURI;
  string private notRevealedURI;

  uint256 private gen0Price = 0.1 ether;
  uint256 private gen1Price = 1500 * 10 ** 18; //5.250.000
  uint256 private gen2Price = 2000 * 10 ** 18; //8.000.000
  // Address of $GalaxyWars Token
  IERC20 public Token;

  event NFTStolen(uint256 tokenId);

  modifier onlyStaking() {
    require(_msgSender() == stakingContract);
    _;
  }

  constructor(IERC20 _token, address[] memory _wallets, uint256[] memory _percentages) {
    Token = _token;
    uint256 total;
    require(_wallets.length == _percentages.length, 'Invalid Input');
    for (uint256 i; i < _wallets.length; i++) {
      claimWallets.push(_wallets[i]);
      claimAmounts[_wallets[i]] = _percentages[i];
      total += _percentages[i];
    }
    require(total == 100, 'Total percentages must add up to 100');
    _pause();
  }

  /// @dev Public Functions
  function skip(uint256 amount) public onlyOwner {
    _circulatingSupply += amount;
  }

  function test(uint256 _amount) public onlyOwner {
    for (uint256 i; i < _amount; i++) {
      _circulatingSupply++;
      _safeMint(_msgSender(), _circulatingSupply);
    }
  }

  function flipSale() external onlyOwner {
    _unpause();
  }

  function getCurrentPrice() external view returns (uint256) {
    uint8 gen;
    if (_circulatingSupply <= 2500) gen = 0;
    else if (_circulatingSupply > 2500 && _circulatingSupply <= 6000) gen = 1;
    else if (_circulatingSupply > 6000 && _circulatingSupply <= 10000) gen = 2;
    else return 0;

    return _getCurrentPrice(gen);
  }

  function getNumOfMintedSoldiers() public view returns (uint256) {
    return mintedSoldiers.length;
  }

  function getNumOfMintedOfficers() public view returns (uint256) {
    return mintedOfficers.length;
  }

  function getNumOfMintedGenerals() public view returns (uint256) {
    return mintedGenerals.length;
  }

  function getNFTRarity(uint256 tokenID) external view virtual returns (uint8) {
    require(_revealed, 'Tokens were not yet revealed');
    require(_exists(tokenID), 'Token does not exist');
    return _nftMetadata[tokenID]._nftType;
  }

  function getNFTGen(uint256 tokenID) external view virtual returns (uint8) {
    require(_revealed, 'Tokens were not yet revealed');
    require(_exists(tokenID), 'Token does not exist');
    return _nftMetadata[tokenID].gen;
  }

  function getNFTMetadata(uint256 tokenID) external view virtual returns (uint8, uint8) {
    require(_revealed, 'Tokens were not yet revealed');
    require(_exists(tokenID), 'Token does not exist');
    return (_nftMetadata[tokenID]._nftType, _nftMetadata[tokenID].gen);
  }

  function isInWhitelist(address _address) external view returns (bool) {
    return whitelist[_address];
  }

  function getStolenNFTs() external view returns (uint256) {
    return stolenNFTs.length;
  }

  function list(uint256 _amount) external {
    require(usedLists[_msgSender()] + _amount <= lists[_msgSender()], 'Insufficient mints');
    usedLists[_msgSender()] += _amount;
    for (uint256 i; i < _amount; i++) {
      _circulatingSupply++;
      _safeMint(_msgSender(), _circulatingSupply);
    }
  }

  function mint(uint256 _amount) external payable whenNotPaused {
    require(_circulatingSupply + _amount <= 10000, 'All tokens were minted');
    uint256 price;
    if (_circulatingSupply < 2500 && _circulatingSupply + _amount < 2500) {
      price = _getCurrentPrice(0);
      require(msg.value >= _amount * price);
      if (whitelistOnly) require(whitelist[_msgSender()], 'Address is not in whitelist');

      payable(claimWallets[1]).transfer(msg.value - (_amount * price));
    } else if (_circulatingSupply < 2500 && _circulatingSupply + _amount >= 2500) {
      uint256 firstGenAmount = _circulatingSupply + _amount - 2500;
      uint256 zeroGenAmount = _amount - firstGenAmount;
      price = _getCurrentPrice(0);
      uint256 _2price = _getCurrentPrice(1);
      uint256 total = zeroGenAmount * price;
      require(msg.value >= total);
      payable(claimWallets[1]).transfer(msg.value - total);
      Token.safeTransferFrom(_msgSender(), address(this), firstGenAmount * _2price);
    } else if (_circulatingSupply >= 2500 && _circulatingSupply + _amount < 6000) {
      price = _getCurrentPrice(1);
      Token.safeTransferFrom(_msgSender(), address(this), _amount * price);
    } else if (_circulatingSupply >= 2500 && _circulatingSupply + _amount >= 6000 && _circulatingSupply < 6000) {
      uint256 secondGenAmount = _circulatingSupply + _amount - 6000;
      uint256 firstGenAmount = _amount - secondGenAmount;
      price = _getCurrentPrice(1);
      uint256 _2price = _getCurrentPrice(2);
      uint256 total = secondGenAmount * _2price + firstGenAmount * price;
      Token.safeTransferFrom(_msgSender(), address(this), total);
    } else if (_circulatingSupply >= 6000) {
      price = _getCurrentPrice(2);
      Token.safeTransferFrom(_msgSender(), address(this), _amount * price);
    }
    for (uint256 i; i < _amount; i++) {
      _circulatingSupply++;
      _safeMint(_msgSender(), _circulatingSupply);
      if (_circulatingSupply == 2500) {
        IStaking(stakingContract).startFarming(block.timestamp);
      }
    }
  }

  function withdrawFunds() external {
    require(claimAmounts[_msgSender()] > 0, 'Contract: Unauthorised call');
    uint256 nBal = address(this).balance;
    for (uint256 i; i < claimWallets.length; i++) {
      address to = claimWallets[i];
      if (nBal > 0) payable(to).transfer((nBal * claimAmounts[to]) / 100);
    }
    if (Token.balanceOf(address(this)) > 0) Token.safeTransfer(owner(), Token.balanceOf(address(this)));
  }

  /// @dev onlyOwner Functions

  function setTempoPrice(uint8 gen, uint256 newPrice, uint256 startTime) external onlyOwner {
    if (startTime == 0) startTime = block.timestamp;

    priceChange[gen].startTime = startTime;
    priceChange[gen].newPrice = newPrice;
  }

  function setList(bool value) external onlyOwner {
    listEnabled = value;
  }

  function setLists(address[] memory addresses, uint256 amount) external onlyOwner {
    for (uint256 i; i < addresses.length; i++) {
      lists[addresses[i]] = amount;
    }
  }

  function changeMintPrice(uint256 _gen0Price, uint256 _gen1Price, uint256 _gen2Price) external onlyOwner {
    gen0Price = _gen0Price * 10 ** 16;
    gen1Price = _gen1Price * 10 ** 18;
    gen2Price = _gen2Price * 10 ** 18;
  }

  function setStartSteal(uint256 start) public onlyOwner {
    _startSteal = start;
  }

  function addGenerals(uint256[] memory _generalsIds) external onlyOwner {
    for (uint256 i; i < _generalsIds.length; i++) {
      _nftMetadata[_generalsIds[i]]._nftType = 2;
    }
    _enteredGenerals += _generalsIds.length;
    require(_enteredGenerals <= _totalGenerals, 'Generals amount would be exceeded');
  }

  function addOfficers(uint256[] memory _officersIds) external onlyOwner {
    for (uint256 i; i < _officersIds.length; i++) {
      _nftMetadata[_officersIds[i]]._nftType = 1;
    }
    _enteredOfficers += _officersIds.length;
    require(_enteredOfficers <= _totalOfficers, 'Officers amount would be exceeded');
  }

  function reveal() external onlyOwner {
    _revealed = true;
  }

  function setBaseURI(string memory _newBaseURI) external onlyOwner {
    baseURI = _newBaseURI;
  }

  function setNotRevealedURI(string memory _newNotRevealedURI) external onlyOwner {
    notRevealedURI = _newNotRevealedURI;
  }

  function setStakingContract(address _address) external onlyOwner {
    stakingContract = _address;
  }

  function withdrawAnyToken(IERC20 asset) external onlyOwner {
    asset.safeTransfer(owner(), asset.balanceOf(address(this)));
  }

  function setWhitelistStatus(bool value) external onlyOwner {
    whitelistOnly = value;
  }

  function addToWhitelist(address _address) external onlyOwner {
    _addToWhitelist(_address);
  }

  function addMultipleToWhitelist(address[] memory _addresses) external onlyOwner {
    for (uint256 i; i < _addresses.length; i++) {
      _addToWhitelist(_addresses[i]);
    }
  }

  function _getCurrentPrice(uint8 gen) internal view returns (uint256) {
    require(gen < 3, 'Invalid Generation');
    if (block.timestamp <= priceChange[gen].startTime + 3600) return priceChange[gen].newPrice;
    else {
      if (gen == 0) return gen0Price;
      else if (gen == 1) return gen1Price;
      else if (gen == 2) return gen2Price;
      else revert();
    }
  }

  function _addToWhitelist(address _address) internal {
    whitelist[_address] = true;
  }

  function retrieveStolenNFTs() external onlyStaking returns (bool returned, uint256[] memory) {
    uint256[] memory transferredNFTs = new uint256[](pendingStolenNFTs.length);
    if (pendingStolenNFTs.length > 0) {
      for (uint256 i; i < pendingStolenNFTs.length; i++) {
        _transfer(address(this), stakingContract, pendingStolenNFTs[i]);
        transferredNFTs[i] = pendingStolenNFTs[i];
      }
      returned = true;
      delete pendingStolenNFTs;
    } else returned = false;

    return (returned, transferredNFTs);
  }

  /// @dev ERC721 Functions

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
    return
      interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC721Metadata).interfaceId || super.supportsInterface(interfaceId);
  }

  function totalSupply() public view virtual returns (uint256) {
    return _totalSupply;
  }

  function cirulatingSupply() public view returns (uint256) {
    return _circulatingSupply;
  }

  function balanceOf(address owner) public view virtual override returns (uint256) {
    require(owner != address(0), 'ERC721: balance query for the zero address');
    return _balances[owner];
  }

  function ownerOf(uint256 tokenId) public view virtual override returns (address) {
    address owner = _owners[tokenId];
    require(owner != address(0), 'ERC721: owner query for nonexistent token');
    return owner;
  }

  function name() public view virtual override returns (string memory) {
    return _name;
  }

  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    require(_exists(tokenId), 'ERC721Metadata: URI query for nonexistent token');

    if (_revealed) {
      string memory baseURI_ = _baseURI();
      return bytes(baseURI_).length > 0 ? string(abi.encodePacked(baseURI_, tokenId.toString())) : '';
    } else return string(abi.encodePacked(notRevealedURI, tokenId.toString()));
  }

  function _baseURI() internal view virtual returns (string memory) {
    return baseURI;
  }

  function approve(address to, uint256 tokenId) public virtual override whenNotPaused {
    address owner = ownerOf(tokenId);
    require(to != owner, 'ERC721: approval to current owner');

    require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), 'ERC721: approve caller is not owner nor approved for all');

    _approve(to, tokenId);
  }

  function getApproved(uint256 tokenId) public view virtual override returns (address) {
    require(_exists(tokenId), 'ERC721: approved query for nonexistent token');

    return _tokenApprovals[tokenId];
  }

  function setApprovalForAll(address operator, bool approved) public virtual override whenNotPaused {
    _setApprovalForAll(_msgSender(), operator, approved);
  }

  function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
    return _operatorApprovals[owner][operator];
  }

  function transferFrom(address from, address to, uint256 tokenId) public virtual override {
    //solhint-disable-next-line max-line-length
    require(_isApprovedOrOwner(_msgSender(), tokenId), 'ERC721: transfer caller is not owner nor approved');

    _transfer(from, to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
    safeTransferFrom(from, to, tokenId, '');
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
    require(_isApprovedOrOwner(_msgSender(), tokenId), 'ERC721: transfer caller is not owner nor approved');
    _safeTransfer(from, to, tokenId, _data);
  }

  function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal virtual {
    _transfer(from, to, tokenId);
    require(_checkOnERC721Received(from, to, tokenId, _data), 'ERC721: transfer to non ERC721Receiver implementer');
  }

  function _exists(uint256 tokenId) internal view virtual returns (bool) {
    return _owners[tokenId] != address(0);
  }

  function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
    require(_exists(tokenId), 'ERC721: operator query for nonexistent token');
    address owner = ownerOf(tokenId);
    return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
  }

  function _safeMint(address to, uint256 tokenId) internal virtual {
    _safeMint(to, tokenId, '');
  }

  function _safeMint(address to, uint256 tokenId, bytes memory _data) internal virtual {
    _mint(to, tokenId);
    require(_checkOnERC721Received(address(0), to, tokenId, _data), 'ERC721: transfer to non ERC721Receiver implementer');
  }

  function _mint(address to, uint256 tokenId) internal virtual {
    require(to != address(0), 'ERC721: mint to the zero address');
    require(!_exists(tokenId), 'ERC721: token already minted');

    if (tokenId <= 2500) _nftMetadata[tokenId].gen = 0;
    else if (tokenId > 2500 && tokenId <= 6000) _nftMetadata[tokenId].gen = 1;
    else if (tokenId > 6000) _nftMetadata[tokenId].gen = 2;

    if (_nftMetadata[tokenId]._nftType == 1) mintedOfficers.push(tokenId);
    else if (_nftMetadata[tokenId]._nftType == 2) mintedGenerals.push(tokenId);
    else mintedSoldiers.push(tokenId);

    bool stolen;
    if (_nftMetadata[tokenId].gen > 0) stolen = _stealMint(tokenId);

    if (stolen) to = address(this);

    _balances[to] += 1;
    _owners[tokenId] = to;

    _beforeTokenTransfer(address(0), to, tokenId);
    emit Transfer(address(0), to, tokenId);
  }

  function _stealMint(uint256 tokenId) internal virtual returns (bool stolen) {
    require(_nftMetadata[tokenId].gen > 0, 'NFT is gen 0');

    if (tokenId % 100 >= _startSteal && tokenId % 100 <= _startSteal + 15) {
      stolen = true;
      stolenNFTs.push(tokenId);
      pendingStolenNFTs.push(tokenId);
      emit NFTStolen(tokenId);
    } else stolen = false;
  }

  function _transfer(address from, address to, uint256 tokenId) internal virtual {
    require(ownerOf(tokenId) == from, 'ERC721: transfer from incorrect owner');
    require(to != address(0), 'ERC721: transfer to the zero address');

    _beforeTokenTransfer(from, to, tokenId);

    _approve(address(0), tokenId);

    _balances[from] -= 1;
    _balances[to] += 1;
    _owners[tokenId] = to;

    emit Transfer(from, to, tokenId);
  }

  function _approve(address to, uint256 tokenId) internal virtual {
    _tokenApprovals[tokenId] = to;
    emit Approval(ownerOf(tokenId), to, tokenId);
  }

  function _setApprovalForAll(address owner, address operator, bool approved) internal virtual {
    require(owner != operator, 'ERC721: approve to caller');
    _operatorApprovals[owner][operator] = approved;
    emit ApprovalForAll(owner, operator, approved);
  }

  function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data) private returns (bool) {
    if (to.isContract()) {
      try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
        return retval == IERC721Receiver.onERC721Received.selector;
      } catch (bytes memory reason) {
        if (reason.length == 0) revert('ERC721: transfer to non ERC721Receiver implementer');
        else
          assembly {
            revert(add(32, reason), mload(reason))
          }
      }
    } else return true;
  }

  function getUserNFTIds(address user) public view returns (uint256[] memory) {
    return ownerToTokens[user].values();
  }

  function getUserMetadata(address user) public view returns (string[] memory) {
    string[] memory userMetadata = new string[](getUserNFTIds(user).length);
    for (uint256 i; i < getUserNFTIds(user).length; i++) {
      userMetadata[i] = tokenURI(getUserNFTIds(user)[i]);
    }
    return userMetadata;
  }

  function _beforeTokenTransfer(address from, address to, uint256 _tokenId) internal virtual {
    ownerToTokens[to].add(_tokenId);
    ownerToTokens[from].remove(_tokenId);
  }
}
