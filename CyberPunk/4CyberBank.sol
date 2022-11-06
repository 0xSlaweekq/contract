// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract ReentrancyGuard {
    /**
     * @dev We use a single lock for the whole contract.
     */
    bool private rentrancy_lock = false;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * @notice If you mark a function `nonReentrant`, you should also
     * mark it `external`. Calling one nonReentrant function from
     * another is not supported. Instead, you can implement a
     * `private` function doing the actual work, and a `external`
     * wrapper marked as `nonReentrant`.
     */
    modifier nonReentrant() {
        require(!rentrancy_lock);
        rentrancy_lock = true;
        _;
        rentrancy_lock = false;
    }
}

contract CyberBank is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint16;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 totalReward;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;
        IERC20 rewardToken;
        uint256 acc_token_precision;
        uint256 amount;
        uint256 rewardForEachBlock;
        uint256 lastRewardBlock;
        uint256 accTokenPerShare;
        uint256 startBlock;
        uint256 endBlock;
        uint256 rewarded;
    }

    uint8 public constant ZERO = 0;
    uint16 public constant RATIO_BASE = 1000;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event HarvestAndRestake(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyStop(address indexed user);
    event Add(
        uint256 rewardForEachBlock,
        IERC20 lpToken,
        bool withUpdate,
        uint256 startBlock,
        uint256 endBlock,
        bool withTokenTransfer
    );
    event SetPoolInfo(uint256 pid, uint256 rewardsTotal, bool withUpdate, uint256 startBlock, uint256 endBlock);
    event ClosePool(uint256 pid);

    event AddRewardForPool(uint256 pid, uint256 addTokenPerBlock, bool withTokenTransfer);

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, 'Pool does not exist');
        _;
    }

    constructor() {}

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // Zero lpToken represents HT pool.
    function add(
        uint256 _totalReward,
        IERC20 _lpToken,
        IERC20 _rewardToken,
        bool _withUpdate,
        uint256 _startBlock,
        uint256 _endBlock,
        bool _withTokenTransfer
    ) external onlyOwner {
        //require(_lpToken != IERC20(ZERO), "lpToken can not be zero!");
        require(_totalReward > ZERO, 'rewardForEachBlock must be greater than zero!');
        require(_startBlock < _endBlock, 'start block must less than end block!');
        if (_withUpdate) {
            massUpdatePools();
        }
        if (_rewardToken != IERC20(address(0))) {
            _totalReward = _totalReward * 10**uint256(_rewardToken.decimals());
        } else {
            _totalReward = _totalReward * 10**18;
        }
        uint256 _rewardForEachBlock = _totalReward.div(_endBlock.sub(_startBlock));

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                rewardToken: _rewardToken,
                acc_token_precision: 10**uint256(_rewardToken.decimals()),
                amount: ZERO,
                rewardForEachBlock: _rewardForEachBlock,
                lastRewardBlock: block.number > _startBlock ? block.number : _startBlock,
                accTokenPerShare: ZERO,
                startBlock: _startBlock,
                endBlock: _endBlock,
                rewarded: ZERO
            })
        );
        if (_withTokenTransfer) {
            uint256 amount = (_endBlock - (block.number > _startBlock ? block.number : _startBlock)).mul(
                _rewardForEachBlock
            );
            _rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        }
        emit Add(_rewardForEachBlock, _lpToken, _withUpdate, _startBlock, _endBlock, _withTokenTransfer);
    }

    // Update the given pool's pool info. Can only be called by the owner.
    function setPoolInfo(
        uint256 _pid,
        uint256 _totalReward,
        bool _withUpdate,
        uint256 _startBlock,
        uint256 _endBlock
    ) external validatePoolByPid(_pid) onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        PoolInfo storage pool = poolInfo[_pid];
        if (_startBlock > ZERO) {
            if (_endBlock > ZERO) {
                require(_startBlock < _endBlock, 'start block must less than end block!');
            } else {
                require(_startBlock < pool.endBlock, 'start block must less than end block!');
            }
            pool.startBlock = _startBlock;
        }
        if (_endBlock > ZERO) {
            if (_startBlock <= ZERO) {
                require(pool.startBlock < _endBlock, 'start block must less than end block!');
            }
            pool.endBlock = _endBlock;
        }
        if (_totalReward > ZERO) {
            uint256 _rewardForEachBlock = _totalReward.div(pool.endBlock.sub(pool.startBlock));
            pool.rewardForEachBlock = _rewardForEachBlock;
        }
        emit SetPoolInfo(_pid, _totalReward, _withUpdate, _startBlock, _endBlock);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        if (_to > _from) {
            return _to.sub(_from);
        }
        return ZERO;
    }

    /// @return APR for 1 year
    function getAPR(uint256 _pid) public view validatePoolByPid(_pid) returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        return (pool.rewardForEachBlock * 20 * 60 * 24 * 365 * 10**18) / pool.amount;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (block.number < pool.startBlock) {
            return;
        }
        if (pool.lastRewardBlock >= pool.endBlock) {
            return;
        }
        if (pool.lastRewardBlock < pool.startBlock) {
            pool.lastRewardBlock = pool.startBlock;
        }
        uint256 multiplier;
        if (block.number > pool.endBlock) {
            multiplier = getMultiplier(pool.lastRewardBlock, pool.endBlock);
            pool.lastRewardBlock = pool.endBlock;
        } else {
            multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            pool.lastRewardBlock = block.number;
        }
        uint256 lpSupply = pool.amount;
        if (lpSupply <= ZERO) {
            return;
        }
        uint256 tokenReward = multiplier.mul(pool.rewardForEachBlock);
        if (tokenReward > ZERO) {
            uint256 poolTokenReward = tokenReward;
            pool.accTokenPerShare = pool.accTokenPerShare.add(
                poolTokenReward.mul(pool.acc_token_precision).div(lpSupply)
            );
        }
    }

    function pendingReward(uint256 _pid, address _user)
        public
        view
        validatePoolByPid(_pid)
        returns (uint256 tokenReward)
    {
        PoolInfo storage pool = poolInfo[_pid];
        if (_user == address(0)) {
            _user = msg.sender;
        }
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.amount;
        uint256 lastRewardBlock = pool.lastRewardBlock;
        if (lastRewardBlock < pool.startBlock) {
            lastRewardBlock = pool.startBlock;
        }
        if (
            block.number > lastRewardBlock &&
            block.number >= pool.startBlock &&
            lastRewardBlock < pool.endBlock &&
            lpSupply > ZERO
        ) {
            uint256 multiplier = ZERO;
            if (block.number > pool.endBlock) {
                multiplier = getMultiplier(lastRewardBlock, pool.endBlock);
            } else {
                multiplier = getMultiplier(lastRewardBlock, block.number);
            }
            uint256 poolTokenReward = multiplier.mul(pool.rewardForEachBlock).div(RATIO_BASE);
            accTokenPerShare = accTokenPerShare.add(poolTokenReward.mul(pool.acc_token_precision).div(lpSupply));
        }
        tokenReward = user.amount.mul(accTokenPerShare).div(pool.acc_token_precision).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = ZERO; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function deposit(uint256 _pid, uint256 _amount) external payable validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        require(block.number <= pool.endBlock, 'this pool has ended!');
        require(block.number >= pool.startBlock, 'this pool has not started!');
        UserInfo storage user = userInfo[_pid][msg.sender];
        harvest(_pid, msg.sender);
        if (pool.lpToken != IERC20(address(0))) {
            _amount = _amount * 10**uint256(pool.lpToken.decimals());
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            _amount = _amount * 10**18;
            require(_amount == msg.value, 'msg.value must be equals to amount!');
        }
        pool.amount = pool.amount.add(_amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(pool.acc_token_precision);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function isMainnetToken(address _token) private pure returns (bool) {
        return _token == address(0);
    }

    // Withdraw LP tokens from CyberBank.
    function withdraw(uint256 _pid, uint256 _amount) external validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(block.number >= pool.startBlock, 'this pool has not started!');
        if (pool.lpToken != IERC20(address(0))) {
            _amount = _amount * 10**uint256(pool.lpToken.decimals());
        } else if (pool.lpToken == IERC20(address(0))) {
            _amount = _amount * 10**18;
        }
        require(user.amount >= _amount, 'withdraw: not good');
        harvest(_pid, msg.sender);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(pool.acc_token_precision);
        pool.amount = pool.amount.sub(_amount);

        if (pool.lpToken != IERC20(address(0))) {
            pool.lpToken.safeTransfer(msg.sender, _amount);
        } else {
            //if pool is HT
            transferMainnetToken(payable(msg.sender), _amount);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    //transfer HT
    function transferMainnetToken(address payable _to, uint256 _amount) internal {
        _to.transfer(_amount);
    }

    function harvest(uint256 _pid, address _to)
        public
        payable
        nonReentrant
        validatePoolByPid(_pid)
        returns (bool success)
    {
        if (_to == address(0)) {
            _to = msg.sender;
        }
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_to];
        if (user.amount != 0) {
            updatePool(_pid);
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(pool.acc_token_precision).sub(user.rewardDebt);
            if (pending > ZERO) {
                success = true;
                if (pool.rewardToken == IERC20(address(0))) {
                    transferMainnetToken(payable(_to), pending);
                } else {
                    safeTransferTokenFromThis(pool.rewardToken, _to, pending);
                }
                pool.rewarded = pool.rewarded.add(pending);
                user.totalReward = user.totalReward.add(pending);
                user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(pool.acc_token_precision);
            } else {
                success = false;
            }
            emit Harvest(_to, _pid, pending);
        }
    }

    function emergencyStop() public onlyOwner {
        uint256 length = poolInfo.length;
        for (uint256 pid = ZERO; pid < length; ++pid) {
            closePool(pid);
        }
        emit EmergencyStop(msg.sender);
    }

    function closePool(uint256 _pid) public validatePoolByPid(_pid) onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp < pool.endBlock) {
            uint256 rewardDiff = pool.rewardForEachBlock.mul(pool.endBlock.sub(block.timestamp));
            if (pool.rewardToken != IERC20(address(0))) {
                pool.rewardToken.safeTransfer(_msgSender(), rewardDiff);
            } else {
                transferMainnetToken(_msgSender(), rewardDiff);
            }
        }
        pool.endBlock = block.number;
        emit ClosePool(_pid);
    }

    // Safe transfer token function, just in case if rounding error causes pool to not have enough tokens.
    function safeTransferTokenFromThis(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) internal {
        uint256 bal = _token.balanceOf(address(this));
        if (_amount > bal) {
            _token.safeTransfer(_to, bal);
        } else {
            _token.safeTransfer(_to, _amount);
        }
    }

    function addRewardForPool(
        uint256 _pid,
        uint256 _addTotalTokens,
        bool _withTokenTransfer
    ) external validatePoolByPid(_pid) onlyOwner {
        require(_addTotalTokens > ZERO, 'add token must be greater than zero!');
        PoolInfo storage pool = poolInfo[_pid];
        require(block.number < pool.endBlock, 'this pool has ended!');
        updatePool(_pid);

        if (pool.rewardToken != IERC20(address(0))) {
            _addTotalTokens = _addTotalTokens * 10**uint256((pool.rewardToken.decimals()));
        } else {
            _addTotalTokens = _addTotalTokens * 10**18;
        }

        uint256 addTokenPerBlock;
        if (block.number < pool.startBlock) {
            addTokenPerBlock = _addTotalTokens.div(pool.endBlock.sub(pool.startBlock));
        } else {
            addTokenPerBlock = _addTotalTokens.div(pool.endBlock.sub(block.number));
        }

        pool.rewardForEachBlock = pool.rewardForEachBlock.add(addTokenPerBlock);
        if (_withTokenTransfer) {
            pool.rewardToken.safeTransferFrom(msg.sender, address(this), _addTotalTokens);
        }
        emit AddRewardForPool(_pid, _addTotalTokens, _withTokenTransfer);
    }
}
