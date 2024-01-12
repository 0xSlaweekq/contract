// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./SetParams.sol";

contract RubicLP is ERC721, SetParams {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20 public immutable USDC;
    IERC20 public immutable BRBC;

    constructor(address usdcAddress, address brbcAddress) ERC721("Rubic LP Token", "RLP") {
        USDC = IERC20(usdcAddress);
        BRBC = IERC20(brbcAddress);
    }

    // USDC amount in
    // BRBC amount in
    // Start period of stake
    // End period of stake
    // true -> recieving rewards, false -> doesn't recieve
    // Stake was created via stakeWhitelist
    // Parameter that represesnts rewards for token
    struct TokenLP {
        uint256 tokenId;
        uint256 USDCAmount;
        uint256 BRBCAmount;
        uint32 startTime;
        uint32 deadline;
        bool isStaked;
        bool isWhitelisted;
        uint256 lastRewardGrowth;
    }

    TokenLP[] public tokensLP;

    // Parameter that represesnts our rewards
    uint256 public rewardGrowth = 1;

    // Mapping that stores all token ids of an owner (owner => tokenIds[])
    mapping(address => EnumerableSet.UintSet) internal ownerToTokens;

    event Stake(address from, address to, uint256 amountUsdc, uint256 amountBrbc, uint256 period, uint256 tokenId);

    /// @dev Prevents using unstaked tokens
    /// @param _tokenId the id of a token
    modifier isInStake(uint256 _tokenId) {
        require(tokensLP[_tokenId].isStaked, "Stake requested for withdraw");
        _;
    }

    /// @dev Internal function that mints LP
    /// @param _USDCAmount the amount of USDC in
    function _mintLP(uint256 _USDCAmount, bool _whitelisted) internal {
        USDC.transferFrom(msg.sender, crossChain, _USDCAmount);
        BRBC.transferFrom(msg.sender, address(this), _USDCAmount * 4);
        uint256 _tokenId = tokensLP.length;
        tokensLP.push(
            TokenLP(
                _tokenId,
                _USDCAmount,
                _USDCAmount * 4,
                uint32(block.timestamp),
                uint32(endTime),
                true,
                _whitelisted,
                rewardGrowth
            )
        );
        poolUSDC += _USDCAmount;
        poolBRBC += _USDCAmount * 4;

        ownerToTokens[msg.sender].add(_tokenId);

        _mint(msg.sender, _tokenId);

        emit Stake(address(0), msg.sender, _USDCAmount, _USDCAmount * 4, endTime, _tokenId);
    }

    /// @dev Internal function which burns LP tokens, clears data from mappings, arrays
    /// @param _tokenId token id that will be burnt
    function _burnLP(uint256 _tokenId) internal {
        ownerToTokens[msg.sender].remove(_tokenId);
        _burn(_tokenId);
    }

    /// @dev private function which is used to transfer stakes
    /// @param _from the sender address
    /// @param _to the recipient
    /// @param _tokenId token id
    function _transferLP(address _from, address _to, uint256 _tokenId) internal isInStake(_tokenId) {
        ownerToTokens[_from].remove(_tokenId);
        ownerToTokens[_to].add(_tokenId);
        _transfer(_from, _to, _tokenId);
    }

    // ERC721 override functions

    function approve(address, uint256) public virtual override {
        revert("Approve forbidden");
    }

    function getApproved(uint256) public view virtual override returns (address operator) {
        revert("Approve forbidden");
    }

    function setApprovalForAll(address, bool) public virtual override {
        revert("Approve forbidden");
    }

    function isApprovedForAll(address, address) public view virtual override returns (bool flag) {
        revert("Approve forbidden");
    }

    function transferFrom(address, address, uint256) public virtual override {
        revert("transferFrom forbidden");
    }

    function safeTransferFrom(address, address, uint256) public virtual override {
        revert("transferFrom forbidden");
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public virtual override {
        revert("transferFrom forbidden");
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
