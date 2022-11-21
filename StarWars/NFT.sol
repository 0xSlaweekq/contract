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
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

interface IForceNFT {
    function getNFTRarity(uint256 tokenID) external view returns (uint8);

    function getNFTGen(uint256 tokenID) external view returns (uint8);

    function getNFTMetadata(uint256 tokenID) external view returns (uint8, uint8);

    function retrieveStolenNFTs() external returns (bool, uint256[] memory);
}

contract ForceNFT is ERC165, IERC721, IERC721Metadata, Ownable {
    using Address for address;
    using Strings for uint256;
    using SafeERC20 for IERC20;

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
        Gen 1 - from 5001 to 10000
        Gen 2 - from 10001 to 20000
         */
        uint8 gen;
    }

    uint256[] private mintedSoldiers;
    uint256[] private mintedOfficers;
    uint256[] private mintedGenerals;
    uint256[] private stolenNFTs;
    uint256[] private pendingStolenNFTs;

    // Token name
    string private _name = 'Force NFT';

    // Token symbol
    string private _symbol = 'FNFT';

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 private _totalSupply = 20000;
    uint256 private _circulatingSupply;

    uint256 private _startSteal;

    mapping(uint256 => NFTMetadata) private _nftMetadata;

    mapping(address => bool) private whitelist;
    bool public whitelistOnly;

    address stakingContract;

    bool public _revealed;

    string private baseURI;
    string private notRevealedURI;

    uint256 private gen0Price = 1 * 10 ** 18;
    uint256 private gen1Price = 3000 * 10 ** 18;
    uint256 private gen2Price = 5000 * 10 ** 18;
    // Address of $Force Token
    IERC20 public Token;

    event NFTStolen(uint256 tokenId);

    modifier onlyStaking() {
        require(_msgSender() == stakingContract);
        _;
    }

    constructor(IERC20 _token) {
        Token = _token;
    }

    /// @dev Public Functions

    function testMint(uint256 amount) public onlyOwner {
        for (uint256 i; i < amount; i++) {
            _circulatingSupply++;
            _mint(owner(), _circulatingSupply);
        }
    }

    function skip(uint256 i) public onlyOwner {
        _circulatingSupply += i;
    }

    function setStartSteal(uint256 start) public onlyOwner {
        _startSteal = start;
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

    function mint(uint256 _amount) external payable {
        require(_circulatingSupply + _amount <= 20000, 'All tokens were minted');
        if (_circulatingSupply < 5000 && _circulatingSupply + _amount < 5000) {
            require(msg.value >= _amount * gen0Price);
            if (whitelistOnly) {
                require(whitelist[_msgSender()], 'Address is not in whitelist');
            }
            if (msg.value > _amount * gen0Price) {
                payable(msg.sender).transfer(msg.value - _amount * gen0Price);
            }
        } else if (_circulatingSupply < 5000 && _circulatingSupply + _amount >= 5000) {
            uint256 firstGenAmount = _circulatingSupply + _amount - 5000;
            uint256 zeroGenAmount = _amount - firstGenAmount;
            uint256 total = zeroGenAmount * gen0Price;
            require(msg.value >= total);
            if (msg.value > total) {
                payable(msg.sender).transfer(msg.value - total);
            }
            Token.safeTransferFrom(_msgSender(), address(this), firstGenAmount * gen1Price);
        } else if (_circulatingSupply >= 5000 && _circulatingSupply + _amount < 10000) {
            Token.safeTransferFrom(_msgSender(), address(this), _amount * gen1Price);
        } else if (_circulatingSupply >= 5000 && _circulatingSupply + _amount >= 10000 && _circulatingSupply < 10000) {
            uint256 secondGenAmount = _circulatingSupply + _amount - 10000;
            uint256 firstGenAmount = _amount - secondGenAmount;
            uint256 total = secondGenAmount * gen2Price + firstGenAmount * gen1Price;
            Token.safeTransferFrom(_msgSender(), address(this), total);
        } else if (_circulatingSupply >= 10000) {
            Token.safeTransferFrom(_msgSender(), address(this), _amount * gen2Price);
        }

        for (uint256 i; i < _amount; i++) {
            _circulatingSupply++;
            _safeMint(_msgSender(), _circulatingSupply);
        }
    }

    /// @dev onlyOwner Functions

    function addGenerals(uint256[] memory _generalsIds) external onlyOwner {
        require(_generalsIds.length == 50);
        for (uint256 i; i < _generalsIds.length; i++) {
            _nftMetadata[_generalsIds[i]]._nftType = 2;
        }
    }

    function addOfficers(uint256[] memory _officersIds) external onlyOwner {
        for (uint256 i; i < _officersIds.length; i++) {
            _nftMetadata[_officersIds[i]]._nftType = 1;
        }
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

    function withdrawFunds() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
        Token.safeTransfer(owner(), Token.balanceOf(address(this)));
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
        } else {
            returned = false;
        }
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
        } else {
            return string(abi.encodePacked(notRevealedURI));
        }
    }

    function _baseURI() internal view virtual returns (string memory) {
        return baseURI;
    }

    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        require(to != owner, 'ERC721: approval to current owner');

        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), 'ERC721: approve caller is not owner nor approved for all');

        _approve(to, tokenId);
    }

    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        require(_exists(tokenId), 'ERC721: approved query for nonexistent token');

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

        _beforeTokenTransfer(address(0), to, tokenId);

        if (tokenId <= 5000) {
            _nftMetadata[tokenId].gen = 0;
        } else if (tokenId > 5000 && tokenId <= 10000) {
            _nftMetadata[tokenId].gen = 1;
        } else if (tokenId > 10000) {
            _nftMetadata[tokenId].gen = 2;
        }

        if (_nftMetadata[tokenId]._nftType == 1) {
            mintedOfficers.push(tokenId);
        } else if (_nftMetadata[tokenId]._nftType == 2) {
            mintedGenerals.push(tokenId);
        } else {
            mintedSoldiers.push(tokenId);
        }

        bool stolen;
        if (_nftMetadata[tokenId].gen > 0) {
            stolen = _stealMint(tokenId);
        }

        if (stolen) {
            to = address(this);
        }

        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
        _afterTokenTransfer(address(0), to, tokenId);
    }

    function _stealMint(uint256 tokenId) internal virtual returns (bool stolen) {
        require(_nftMetadata[tokenId].gen > 0, 'NFT is gen 0');

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
        require(ownerOf(tokenId) == from, 'ERC721: transfer from incorrect owner');
        require(to != address(0), 'ERC721: transfer to the zero address');

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
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
                if (reason.length == 0) {
                    revert('ERC721: transfer to non ERC721Receiver implementer');
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}
}
