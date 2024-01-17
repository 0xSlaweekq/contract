// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface ICyberPunkMetisGame {
    function getNFTRarity(uint256 tokenID) external view returns (uint8);
    function getNFTGen(uint256 tokenID) external view returns (uint8);
    function getNFTMetadata(uint256 tokenID) external view returns (uint8, uint8);
    function retrieveStolenNFTs() external returns (bool, uint256[] memory);
}

interface IStaking {
    function startFarming(uint256 _startDate) external;
}

contract CyberPunkMetisGame is ERC165, IERC721, IERC721Metadata, Ownable {
    using Address for address;
    using Strings for uint256;
    using SafeERC20 for IERC20;

    struct PriceChange {
        uint256 startTime;
        uint256 newPrice;
    }

    address[] public claimWallets;
    mapping(address => uint256) public claimAmounts;

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
        Gen 0 - from 1 to 5000
        Gen 1 - from 5001 to 15000
        Gen 2 - from 15001 to 25000
         */
        uint8 gen;
    }

    uint256[] private mintedSoldiers;
    uint256[] private mintedOfficers;
    uint256[] private mintedGenerals;
    uint256[] private stolenNFTs;
    uint256[] private pendingStolenNFTs;

    // Token name
    string private _name = "Cyber Punk Metis Game";

    // Token symbol
    string private _symbol = "CyberPunk";

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 private _totalSupply = 25000;
    uint256 private _totalOfficers = 7500;
    uint256 private _totalGenerals = 2500;
    uint256 private _enteredOfficers;
    uint256 private _enteredGenerals;
    uint256 private _circulatingSupply;

    uint256 private _startSteal;

    mapping(uint256 => NFTMetadata) private _nftMetadata;

    mapping(address => bool) private whitelist;

    mapping(address => uint256) public freeMints;
    mapping(address => uint256) public usedFreeMints;
    bool public freeMintEnabled = false;

    bool public whitelistOnly;

    address stakingContract;

    bool public _revealed;

    string private baseURI;
    string private notRevealedURI;

    uint256 private gen0Price = 1 * 10 ** 18;
    uint256 private gen1Price = 30000 * 10 ** 18;
    uint256 private gen2Price = 50000 * 10 ** 18;
    // Address of $NEON Token
    IERC20 public Token;

    event NFTStolen(uint256 tokenId);

    modifier onlyStaking() {
        require(_msgSender() == stakingContract);
        _;
    }

    constructor(IERC20 _token, address[] memory _wallets, uint256[] memory _percentages) {
        Token = _token;
        uint256 total;
        require(_wallets.length == _percentages.length, "Invalid Input");
        for (uint256 i; i < _wallets.length; i++) {
            claimWallets.push(_wallets[i]);
            claimAmounts[_wallets[i]] = _percentages[i];
            total += _percentages[i];
        }
        require(total == 100, "Total percentages must add up to 100");
    }

    /// @dev Public Functions

    /// @dev Test

    function skip(uint256 amount) public onlyOwner {
        _circulatingSupply += amount;
    }

    function testMint(uint256 _amount) public onlyOwner {
        for (uint256 i; i < _amount; i++) {
            _circulatingSupply++;
            _safeMint(_msgSender(), _circulatingSupply);
        }
    }

    /// @dev End Test

    function getCurrentPrice() external view returns (uint256) {
        uint8 gen;
        if (_circulatingSupply <= 5000) gen = 0;
        else if (_circulatingSupply > 5000 && _circulatingSupply <= 15000) gen = 1;
        else if (_circulatingSupply > 15000 && _circulatingSupply <= 25000) gen = 2;
        else return 0;

        return _getCurrentPrice(gen);
    }

    function getUserNFTIds(address user) public view returns (uint256[] memory) {
        uint256[] memory userIds = new uint256[](balanceOf(user));
        for (uint256 i; i < balanceOf(user); i++) {
            userIds[i] = _ownedTokens[user][i];
        }
        return userIds;
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
        require(_revealed, "Tokens were not yet revealed");
        require(_exists(tokenID), "Token does not exist");
        return _nftMetadata[tokenID]._nftType;
    }

    function getNFTGen(uint256 tokenID) external view virtual returns (uint8) {
        require(_revealed, "Tokens were not yet revealed");
        require(_exists(tokenID), "Token does not exist");
        return _nftMetadata[tokenID].gen;
    }

    function getNFTMetadata(uint256 tokenID) external view virtual returns (uint8, uint8) {
        require(_revealed, "Tokens were not yet revealed");
        require(_exists(tokenID), "Token does not exist");
        return (_nftMetadata[tokenID]._nftType, _nftMetadata[tokenID].gen);
    }

    function isInWhitelist(address _address) external view returns (bool) {
        return whitelist[_address];
    }

    function getMintedSoldiers() external view returns (uint256[] memory) {
        return mintedSoldiers;
    }

    function getMintedOfficers() external view returns (uint256[] memory) {
        return mintedOfficers;
    }

    function getMintedGenerals() external view returns (uint256[] memory) {
        return mintedGenerals;
    }

    function getStolenNFTs() external view returns (uint256) {
        return stolenNFTs.length;
    }

    function freeMint(uint256 _amount) external {
        require(usedFreeMints[_msgSender()] + _amount <= freeMints[_msgSender()], "Insufficient free mints");
        usedFreeMints[_msgSender()] += _amount;
        for (uint256 i; i < _amount; i++) {
            _circulatingSupply++;
            _safeMint(_msgSender(), _circulatingSupply);
        }
    }

    function mint(uint256 _amount) external payable {
        require(_circulatingSupply + _amount <= 25000, "All tokens were minted");
        uint256 price;
        if (_circulatingSupply < 5000 && _circulatingSupply + _amount < 5000) {
            price = _getCurrentPrice(0);
            require(msg.value >= _amount * price);
            if (whitelistOnly) require(whitelist[_msgSender()], "Address is not in whitelist");

            if (msg.value > _amount * price) payable(msg.sender).transfer(msg.value - _amount * price);
        } else if (_circulatingSupply < 5000 && _circulatingSupply + _amount >= 5000) {
            uint256 firstGenAmount = _circulatingSupply + _amount - 5000;
            uint256 zeroGenAmount = _amount - firstGenAmount;
            price = _getCurrentPrice(0);
            uint256 _2price = _getCurrentPrice(1);
            uint256 total = zeroGenAmount * price;
            require(msg.value >= total);
            if (msg.value > total) payable(msg.sender).transfer(msg.value - total);

            Token.safeTransferFrom(_msgSender(), address(this), firstGenAmount * _2price);
        } else if (_circulatingSupply >= 5000 && _circulatingSupply + _amount < 15000) {
            price = _getCurrentPrice(1);
            Token.safeTransferFrom(_msgSender(), address(this), _amount * price);
        } else if (_circulatingSupply >= 5000 && _circulatingSupply + _amount >= 15000 && _circulatingSupply < 15000) {
            uint256 secondGenAmount = _circulatingSupply + _amount - 15000;
            uint256 firstGenAmount = _amount - secondGenAmount;
            price = _getCurrentPrice(1);
            uint256 _2price = _getCurrentPrice(2);
            uint256 total = secondGenAmount * _2price + firstGenAmount * price;
            Token.safeTransferFrom(_msgSender(), address(this), total);
        } else if (_circulatingSupply >= 15000) {
            price = _getCurrentPrice(2);
            Token.safeTransferFrom(_msgSender(), address(this), _amount * price);
        }
        for (uint256 i; i < _amount; i++) {
            _circulatingSupply++;
            _safeMint(_msgSender(), _circulatingSupply);
            if (_circulatingSupply == 5000) _startFarming();
        }
    }

    function withdrawFunds() external {
        require(claimAmounts[_msgSender()] > 0, "Contract: Unauthorised call");
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

    function setFreeMint(bool value) external onlyOwner {
        freeMintEnabled = value;
    }

    function setFreeMints(address[] memory addresses, uint256 amount) external onlyOwner {
        for (uint256 i; i < addresses.length; i++) {
            freeMints[addresses[i]] = amount;
        }
    }

    function changeMintPrice(uint256 _gen0Price, uint256 _gen1Price, uint256 _gen2Price) external onlyOwner {
        gen0Price = _gen0Price;
        gen1Price = _gen1Price;
        gen2Price = _gen2Price;
    }

    function setStartSteal(uint256 start) public onlyOwner {
        _startSteal = start;
    }

    function addGenerals(uint256[] memory _generalsIds) external onlyOwner {
        for (uint256 i; i < _generalsIds.length; i++) {
            _nftMetadata[_generalsIds[i]]._nftType = 2;
        }
        _enteredGenerals += _generalsIds.length;
        require(_enteredGenerals <= _totalGenerals, "Generals amount would be exceeded");
    }

    function addOfficers(uint256[] memory _officersIds) external onlyOwner {
        for (uint256 i; i < _officersIds.length; i++) {
            _nftMetadata[_officersIds[i]]._nftType = 1;
        }
        _enteredOfficers += _officersIds.length;
        require(_enteredOfficers <= _totalOfficers, "Officers amount would be exceeded");
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

    function _startFarming() internal {
        require(_circulatingSupply == 5000);
        IStaking(stakingContract).startFarming(block.timestamp);
    }

    function _getCurrentPrice(uint8 gen) internal view returns (uint256) {
        require(gen < 3, "Invalid Generation");
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
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function cirulatingSupply() public view returns (uint256) {
        return _circulatingSupply;
    }

    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        if (_revealed) {
            string memory baseURI_ = _baseURI();
            return bytes(baseURI_).length > 0 ? string(abi.encodePacked(baseURI_, tokenId.toString())) : "";
        } else return string(abi.encodePacked(notRevealedURI));
    }

    function _baseURI() internal view virtual returns (string memory) {
        return baseURI;
    }

    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        if (tokenId <= 5000) _nftMetadata[tokenId].gen = 0;
        else if (tokenId > 5000 && tokenId <= 15000) _nftMetadata[tokenId].gen = 1;
        else if (tokenId > 15000) _nftMetadata[tokenId].gen = 2;

        if (_nftMetadata[tokenId]._nftType == 1) mintedOfficers.push(tokenId);
        else if (_nftMetadata[tokenId]._nftType == 2) mintedGenerals.push(tokenId);
        else mintedSoldiers.push(tokenId);

        bool stolen;
        if (_nftMetadata[tokenId].gen > 0) stolen = _stealMint(tokenId);

        if (stolen) to = address(this);

        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function _stealMint(uint256 tokenId) internal virtual returns (bool stolen) {
        require(_nftMetadata[tokenId].gen > 0, "NFT is gen 0");

        if (tokenId % 100 >= _startSteal && tokenId % 100 <= _startSteal + 15) {
            stolen = true;
            stolenNFTs.push(tokenId);
            pendingStolenNFTs.push(tokenId);
            emit NFTStolen(tokenId);
        } else {
            stolen = false;
        }
    }

    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
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
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) revert("ERC721: transfer to non ERC721Receiver implementer");
                else
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
            }
        } else {
            return true;
        }
    }

    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual returns (uint256) {
        require(index < balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    function tokenByIndex(uint256 index) public view virtual returns (uint256) {
        require(index < totalSupply(), "ERC721Enumerable: global index out of bounds");
        return _allTokens[index];
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {
        if (from == address(0)) _addTokenToAllTokensEnumeration(tokenId);
        else if (from != to) _removeTokenFromOwnerEnumeration(from, tokenId);

        if (to == address(0)) _removeTokenFromAllTokensEnumeration(tokenId);
        else if (to != from) _addTokenToOwnerEnumeration(to, tokenId);
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}
