// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

contract SetParams is AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    /// Cross chain address where USDC goes

    address public crossChain = 0x70e8C8139d1ceF162D5ba3B286380EB5913098c4;
    /// Changeable address of BRBC receiver
    address public penaltyReceiver = 0xC958744795332f1058aF71caaEf89e2BE35105A0;
    uint8 internal constant decimals = 18;

    EnumerableSet.AddressSet internal whitelist;

    // Start time of staking
    uint32 public startTime;
    // End time of stacking
    uint32 public endTime;

    // Maximum amount of USDC / BRBC freezed in pool
    uint256 public maxPoolUSDC;
    uint256 public maxPoolBRBC;

    // Total amount of USDC / BRBC stacked in pool
    uint256 public poolUSDC;
    uint256 public poolBRBC;

    // Minimal amount of USDC to stake at once
    uint256 public minUSDCAmount;
    // Maximum amount for one user to stake
    uint256 public maxUSDCAmount;
    uint256 public maxUSDCAmountWhitelist;
    // Penalty in percents which we will take for early unstake
    uint256 public penalty;

    // Role of the manager
    bytes32 public constant MANAGER = keccak256('MANAGER');

    /// @dev This modifier prevents using manager functions
    modifier onlyManager() {
        require(hasRole(MANAGER, msg.sender), 'Caller is not a manager');
        _;
    }

    function setWhitelist(address[] memory whitelistedAddresses) external onlyManager {
        for (uint256 i = 0; i < whitelistedAddresses.length; i++) {
            whitelist.add(whitelistedAddresses[i]);
        }
    }

    /// @dev onlyManager function that sets time, during which user can start staking his LP
    /// @param _startTime the start time of the staking, greater then now
    /// @param _endTime the end time of the staking, greater then _startTime
    function setTime(uint32 _startTime, uint32 _endTime) external onlyManager {
        require(_startTime >= block.timestamp && _endTime >= _startTime, 'Incorrect time');
        startTime = _startTime;
        endTime = _endTime;
    }

    /// @dev onlyManager function that sets Cross Chain address, where USDC goes
    /// @param _crossChain address of new deployed cross chain pool
    function setCrossChainAddress(address _crossChain) external onlyManager {
        require(crossChain != _crossChain, 'Address already set');
        crossChain = _crossChain;
    }

    /// @dev onlyManager function that sets penalty address, where BRBC goes
    /// @param _penaltyAddress address of new BRBC receiver
    function setPenaltyAddress(address _penaltyAddress) external onlyManager {
        require(penaltyReceiver != _penaltyAddress, 'Address already set');
        penaltyReceiver = _penaltyAddress;
    }

    /// @dev onlyManager function, sets maximum USDC amount which one address can hold
    /// @param _maxUSDCAmount the maximum USDC amount, must be greater then minUSDCAmount
    function setMaxUSDCAmount(uint256 _maxUSDCAmount) external onlyManager {
        require(_maxUSDCAmount > minUSDCAmount, 'Max USDC amount must be greater than min USDC amount');
        maxUSDCAmount = _maxUSDCAmount;
    }

    /// @dev onlyManager function, sets penalty that will be taken for early unstake
    /// @param _penalty amount in percent, sets from 0% to 100% of users stake
    function setPenalty(uint256 _penalty) external onlyManager {
        require(_penalty >= 0 && _penalty <= 1000, 'Incorrect penalty');
        penalty = _penalty;
    }

    /// @dev onlyManager function, sets minimum USDC amount which one address can stake
    /// @param _minUSDCAmount the minimum USDC amount, must be lower then maxUSDCAmount
    function setMinUSDCAmount(uint256 _minUSDCAmount) external onlyManager {
        require(_minUSDCAmount < maxUSDCAmount, 'Min USDC amount must be lower than max USDC amount');
        minUSDCAmount = _minUSDCAmount;
    }

    /// @dev onlyManager function, sets maximum USDC pool size amount
    /// @param _maxPoolUSDC the maximum USDC amount
    function setMaxPoolUSDC(uint256 _maxPoolUSDC) external onlyManager {
        maxPoolUSDC = _maxPoolUSDC;
    }

    /// @dev onlyManager function, sets maximum BRBC pool size amount
    /// @param _maxPoolBRBC the maximum BRBC amount
    function setMaxPoolBRBC(uint256 _maxPoolBRBC) external onlyManager {
        maxPoolBRBC = _maxPoolBRBC;
    }
}
