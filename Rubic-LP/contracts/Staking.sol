// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./libraries/FullMath.sol";
import "./RubicLP.sol";

contract Staking is RubicLP {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint32 immutable requestTime;
    uint32 immutable whitelistTime;
    uint32 immutable lpDuration;

    /// Constant address of BRBC, which is forbidden to owner for withdraw
    address internal constant BRBC_ADDRESS = 0x8E3BCC334657560253B83f08331d85267316e08a;

    // tokenId => amount total collected
    mapping(uint256 => uint256) public collectedRewardsForToken;

    // Total amount of USDC added as Rewards for APR
    uint256 internal totalRewardsAddedToday;
    uint256 public requestedAmount;

    /// List of events
    event AddRewards(address from, address to, uint256 amount);
    event ClaimRewards(address from, address to, uint256 tokenId, uint256 userReward);
    event RequestWithdraw(address requestAddress, uint256 tokenId, uint256 amountUSDC, uint256 amountBRBC);
    event Withdraw(address from, address to, uint256 tokenId, uint256 amountUSDC, uint256 amountBRBC);

    constructor(address usdcAddr, address brbcAddr) RubicLP(usdcAddr, brbcAddr) {
        _setupRole(DEFAULT_ADMIN_ROLE, 0x105A3BA3637A29D36F61c7F03f55Da44B4591Cd1);
        _setupRole(MANAGER, 0x105A3BA3637A29D36F61c7F03f55Da44B4591Cd1);

        // Set up penalty amount in % / 10
        penalty = 100;

        // set up pool size
        requestTime = 1 days;
        whitelistTime = 1 days;
        lpDuration = 61 days;

        minUSDCAmount = 500 * 10 ** decimals;
        maxUSDCAmount = 5000 * 10 ** decimals;
        maxUSDCAmountWhitelist = 800 * 10 ** decimals;

        maxPoolUSDC = 800_000 * 10 ** decimals;
        maxPoolBRBC = 3_200_000 * 10 ** decimals;

        startTime = uint32(1651068000);
        endTime = startTime + lpDuration;

        tokensLP.push(TokenLP(0, 0, 0, 0, 0, false, false, 0));
    }

    /// @dev Prevents calling a function from anyone except the owner,
    /// list all tokens of a user to find a match
    /// @param _tokenId the id of a token
    modifier ownerOfStake(uint256 _tokenId) {
        require(ownerToTokens[msg.sender].contains(_tokenId), "You need to be an owner");
        _;
    }

    /// @dev Prevents withdrawing rewards with zero reward
    /// @param _tokenId token id
    modifier positiveRewards(uint256 _tokenId) {
        require(viewRewards(_tokenId) > 0 && poolUSDC > 0, "You have 0 rewards");
        _;
    }

    /// @dev This modifier prevents one person to own more than max USDC for this address
    /// @param _amount the USDC amount to stake
    modifier maxStakeAmount(uint256 _amount, uint256 _maxUSDCAmount) {
        uint256[] memory ownerTokenList = viewTokensByOwner(msg.sender);
        if (ownerTokenList.length == 0) {
            require(_amount <= _maxUSDCAmount, "Max amount for stake exceeded");
        } else {
            for (uint256 i = 0; i < ownerTokenList.length; i++) {
                _amount += tokensLP[ownerTokenList[i]].USDCAmount;
                require(_amount <= _maxUSDCAmount, "Max amount for stake exceeded");
            }
        }
        _;
    }

    /// @dev This modifier prevents transfer of tokens to self and null addresses
    /// @param _to the token reciever
    modifier transferCheck(address _to) {
        require(_to != msg.sender && _to != address(0), "You cant transfer to yourself or to null address");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelist.contains(msg.sender), "You are not in whitelist");
        _;
    }

    function whitelistStake(uint256 _amountUSDC)
        external
        maxStakeAmount(_amountUSDC, maxUSDCAmountWhitelist)
        onlyWhitelisted
    {
        require(block.timestamp >= startTime, "Whitelist period hasnt started");
        require(block.timestamp < startTime + whitelistTime, "Whitelist staking period ended");
        require(
            poolUSDC + _amountUSDC <= maxPoolUSDC && poolBRBC + (_amountUSDC * 4) <= maxPoolBRBC,
            "Max pool size exceeded"
        );
        require(_amountUSDC >= minUSDCAmount, "Less than minimum stake amount");
        /// Transfer USDC from user to the cross chain, BRBC to this contract, mints LP
        _mintLP(_amountUSDC, true);
    }

    /// @dev Main function, which receives deposit, calls _mintLP LP function, freeze funds
    /// @param _amountUSDC the amount in of USDC
    function stake(uint256 _amountUSDC) external maxStakeAmount(_amountUSDC, maxUSDCAmount) {
        require(block.timestamp >= startTime + whitelistTime, "Staking period hasnt started");
        require(block.timestamp <= endTime, "Staking period has ended");
        require(
            poolUSDC + _amountUSDC <= maxPoolUSDC && poolBRBC + (_amountUSDC * 4) <= maxPoolBRBC,
            "Max pool size exceeded"
        );
        require(_amountUSDC >= minUSDCAmount, "Less than minimum stake amount");
        /// Transfer USDC from user to the cross chain, BRBC to this contract, mints LP
        _mintLP(_amountUSDC, false);
    }

    /// @dev Transfer function, check for validity address to, ownership of the token, the USDC amount of recipient
    /// @param _to the recipient
    /// @param _tokenId the token id
    function transfer(address _to, uint256 _tokenId) external transferCheck(_to) ownerOfStake(_tokenId) {
        _transferLP(msg.sender, _to, _tokenId);
    }

    /// @dev OnlyManager function, adds rewards for users
    /// @param _amount the USDC amount of comission to the pool
    function addRewards(uint256 _amount) external onlyManager {
        require(poolUSDC > 0, "Stakes not created");
        USDC.transferFrom(msg.sender, address(this), _amount);
        totalRewardsAddedToday = _amount;
        rewardGrowth = rewardGrowth + FullMath.mulDiv(_amount, 10 ** 29, poolUSDC);
        emit AddRewards(msg.sender, address(this), _amount);
    }

    /// @dev Withdraw reward USDC from the contract, checks if the reward is positive,
    /// @dev doesn't give permission to use null token
    /// @param _tokenId token id
    function claimRewards(uint256 _tokenId)
        public
        ownerOfStake(_tokenId)
        isInStake(_tokenId)
        positiveRewards(_tokenId)
    {
        uint256 _rewardAmount = viewRewards(_tokenId);
        tokensLP[_tokenId].lastRewardGrowth = rewardGrowth;
        collectedRewardsForToken[_tokenId] += _rewardAmount;
        USDC.transfer(msg.sender, _rewardAmount);
        emit ClaimRewards(address(this), msg.sender, _tokenId, _rewardAmount);
    }

    /// @dev Send a request for withdraw, claims reward, stops staking, penalizes user
    /// @param _tokenId the token id
    function requestWithdraw(uint256 _tokenId) external ownerOfStake(_tokenId) isInStake(_tokenId) {
        if (viewRewards(_tokenId) > 0) {
            claimRewards(_tokenId);
        }
        tokensLP[_tokenId].isStaked = false;

        if (tokensLP[_tokenId].deadline > uint32(block.timestamp + requestTime)) {
            _penalizeAddress(_tokenId);
        }
        // ready for withdraw next day
        tokensLP[_tokenId].deadline = uint32(block.timestamp + requestTime);
        requestedAmount += tokensLP[_tokenId].USDCAmount;
        poolUSDC -= tokensLP[_tokenId].USDCAmount;
        poolBRBC -= tokensLP[_tokenId].BRBCAmount;
        emit RequestWithdraw(msg.sender, _tokenId, tokensLP[_tokenId].USDCAmount, tokensLP[_tokenId].BRBCAmount);
    }

    /// @dev penalizes user, transfer his USDC and BRBC to penaty address
    /// @param _tokenId the token id
    function _penalizeAddress(uint256 _tokenId) internal {
        uint256 penaltyAmountBRBC = (tokensLP[_tokenId].BRBCAmount * penalty) / 1000;
        uint256 penaltyAmountUSDC = (tokensLP[_tokenId].USDCAmount * penalty) / 1000;
        poolBRBC -= penaltyAmountBRBC;
        poolUSDC -= penaltyAmountUSDC;
        tokensLP[_tokenId].BRBCAmount -= penaltyAmountBRBC;
        BRBC.transfer(penaltyReceiver, penaltyAmountBRBC);
        tokensLP[_tokenId].USDCAmount -= penaltyAmountUSDC;
    }

    /// @dev User withdraw his frozen USDC and BRBC after stake
    /// @param _tokenId the token id
    function withdraw(uint256 _tokenId) external ownerOfStake(_tokenId) {
        require(tokensLP[_tokenId].isStaked == false, "Request withdraw first");
        require(tokensLP[_tokenId].deadline < block.timestamp, "Request in process");
        require(tokensLP[_tokenId].USDCAmount <= USDC.balanceOf(address(this)), "Funds hasnt arrived yet");
        uint256 _withdrawAmountUSDC = tokensLP[_tokenId].USDCAmount;
        uint256 _withdrawAmountBRBC = tokensLP[_tokenId].BRBCAmount;
        _burnLP(_tokenId);
        USDC.transfer(msg.sender, _withdrawAmountUSDC);
        BRBC.transfer(msg.sender, _withdrawAmountBRBC);
        emit Withdraw(address(this), msg.sender, _tokenId, _withdrawAmountUSDC, _withdrawAmountBRBC);
    }

    function sweepTokens(address token) external onlyManager {
        require(token != BRBC_ADDRESS, "Rubic sweep is forbidden");
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function fundRequests() external onlyManager {
        require(requestedAmount > 0, "No need to fund");
        USDC.transferFrom(msg.sender, address(this), requestedAmount);
        requestedAmount = 0;
    }

    ///////////////////////// view functions below ////////////////////////////

    /// @dev Shows the amount of rewards that wasn't for a token
    /// @param _tokenId the token id
    /// returns reward in USDC
    function viewRewards(uint256 _tokenId) public view returns (uint256 rewardAmount) {
        if (_tokenId > tokensLP.length - 1) {
            return 0;
        }

        if (tokensLP[_tokenId].isStaked == false) {
            return 0;
        } else {
            return FullMath.mulDiv(
                tokensLP[_tokenId].USDCAmount, rewardGrowth - tokensLP[_tokenId].lastRewardGrowth, 10 ** 29
            );
        }
    }

    /// @dev Shows the amount of rewards that wasn claimed for a token, doesn't give permission to see null token
    /// @param _tokenId the token id
    /// returns reward in USDC
    function viewCollectedRewards(uint256 _tokenId) public view returns (uint256 rewardForTokenClaimed) {
        return collectedRewardsForToken[_tokenId];
    }

    function viewTotalEntered() public view returns (uint256 totalPoolUSDC, uint256 totalPoolBRBC) {
        return (poolUSDC, poolBRBC);
    }

    /// @dev Shows the amount of time left before unlock, returns 0 in case token is already unlocked
    /// @param _tokenId the token id
    function timeBeforeUnlock(uint256 _tokenId) public view returns (uint32) {
        if (tokensLP[_tokenId].deadline > uint32(block.timestamp + requestTime)) {
            return uint32(tokensLP[_tokenId].deadline - block.timestamp);
        } else {
            return 0;
        }
    }

    /// @dev shows total USDC amount of stakes
    /// @param _tokenOwner address of the stake
    /// returns total address USDC amount staked
    function viewUSDCAmountOf(address _tokenOwner) public view returns (uint256 USDCAmount) {
        uint256[] memory ownerTokenList = viewTokensByOwner(_tokenOwner);
        uint256 _USDCAmount;
        for (uint256 i = 0; i < ownerTokenList.length; i++) {
            _USDCAmount += tokensLP[ownerTokenList[i]].USDCAmount;
        }

        return _USDCAmount;
    }

    /// @dev shows total uncollected rewards of address in USDC
    /// returns total uncollected rewards
    function viewRewardsTotal(address _tokenOwner) public view returns (uint256 totalRewardsAmount) {
        uint256[] memory ownerTokenList = viewTokensByOwner(_tokenOwner);
        uint256 _result;
        for (uint256 i = 0; i < ownerToTokens[_tokenOwner].length(); i++) {
            _result += viewRewards(ownerTokenList[i]);
        }
        return _result;
    }

    /// @dev shows total collected rewards of address in USDC
    /// returns total collected rewards
    function viewCollectedRewardsTotal(address _tokenOwner) public view returns (uint256 totalCollectedRewardsAmount) {
        uint256[] memory ownerTokenList = viewTokensByOwner(_tokenOwner);
        uint256 _result;
        for (uint256 i = 0; i < ownerToTokens[_tokenOwner].length(); i++) {
            _result += viewCollectedRewards(ownerTokenList[i]);
        }
        return _result;
    }

    function viewTokensByOwner(address _tokenOwner) public view returns (uint256[] memory tokenList) {
        return ownerToTokens[_tokenOwner].values();
    }

    /// @dev parsed array with all data from token ids
    /// @param _tokenOwner the owner address
    /// returns parsed array with all data from token ids, collected and uncollected rewards
    function infoAboutDepositsParsed(address _tokenOwner)
        external
        view
        returns (
            TokenLP[] memory parsedArrayOfTokens,
            uint256[] memory collectedRewards,
            uint256[] memory rewardsToCollect,
            bool[] memory isWithdrawable
        )
    {
        uint256 _ownerTokensAmount = ownerToTokens[_tokenOwner].length();
        // list of user's tokens ids
        uint256[] memory _tokens = new uint256[](_ownerTokensAmount);
        // list of collected rewards for each token
        uint256[] memory _collectedRewards = new uint256[](_ownerTokensAmount);
        // list of uncollected rewards for each token
        uint256[] memory _rewardsToCollect = new uint256[](_ownerTokensAmount);
        // list of token withdraw status
        bool[] memory _isWithdrawable = new bool[](_ownerTokensAmount);
        // all info about tokensLP
        TokenLP[] memory _parsedArrayOfTokens = new TokenLP[](_ownerTokensAmount);
        _tokens = viewTokensByOwner(_tokenOwner);

        for (uint256 i = 0; i < _tokens.length; i++) {
            _parsedArrayOfTokens[i] = tokensLP[_tokens[i]];
            _collectedRewards[i] = viewCollectedRewards(_tokens[i]);
            _rewardsToCollect[i] = viewRewards(_tokens[i]);
            _isWithdrawable[i] = viewApprovedWithdrawToken(_tokens[i]);
        }
        return (_parsedArrayOfTokens, _collectedRewards, _rewardsToCollect, _isWithdrawable);
    }

    /// @dev calculates current apr for each day
    /// returns current apr
    function apr() public view returns (uint256 aprNum) {
        if (poolUSDC == 0) {
            return 0;
        } else {
            return (FullMath.mulDiv(totalRewardsAddedToday, 10 ** 29, poolUSDC) * 365 * 100);
        }
    }

    /// @dev shows total information about users and pools USDC
    /// @param _tokenOwner the owner address
    /// returns total amount of users USDC, USDC in pool
    function stakingProgressParsed(address _tokenOwner)
        external
        view
        returns (uint256 yourTotalUSDC, uint256 totalUSDCInPoolWhitelist, uint256 totalUSDCInPool)
    {
        uint256 _yourTotalUSDC = viewUSDCAmountOf(_tokenOwner);
        uint256 _totalUSDCInPoolWhitelist;
        uint256 _totalUSDCInPool;
        (_totalUSDCInPoolWhitelist, _totalUSDCInPool) = viewTotalEntered();
        return (_yourTotalUSDC, _totalUSDCInPoolWhitelist, _totalUSDCInPool);
    }

    /// @dev shows data about rewards
    /// @param _tokenOwner the owner address
    /// returns total of collected, uncollected rewards, apr
    function stakingInfoParsed(address _tokenOwner)
        external
        view
        returns (uint256 amountToCollectTotal, uint256 amountCollectedTotal, uint256 aprInfo)
    {
        uint256 _amountToCollectTotal = viewRewardsTotal(_tokenOwner);
        uint256 _amountCollectedTotal = viewCollectedRewardsTotal(_tokenOwner);
        uint256 _apr = apr();
        return (_amountToCollectTotal, _amountCollectedTotal, _apr);
    }

    function viewWhitelistInProgress() public view returns (bool isInProgress) {
        if (startTime + whitelistTime > block.timestamp) {
            return true;
        }
        return false;
    }

    /// @dev Shows the status of the user's token id for withdraw
    /// @param _tokenId the token id
    function viewApprovedWithdrawToken(uint256 _tokenId) public view returns (bool readyForWithdraw) {
        if (
            tokensLP[_tokenId].isStaked == false && tokensLP[_tokenId].deadline < block.timestamp
                && tokensLP[_tokenId].USDCAmount <= USDC.balanceOf(address(this))
        ) {
            return true;
        }
        return false;
    }
}
