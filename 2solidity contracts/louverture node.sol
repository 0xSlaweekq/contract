/*
 *        __                                        __                                  ______    _                                      
 *       / /   ____   __  __ _   __  ___    _____  / /_  __  __   _____  ___           / ____/   (_)   ____   ____ _   ____   _____  ___ 
 *      / /   / __ \ / / / /| | / / / _ \  / ___/ / __/ / / / /  / ___/ / _ \         / /_      / /   / __ \ / __ `/  / __ \ / ___/ / _ \
 *     / /___/ /_/ // /_/ / | |/ / /  __/ / /    / /_  / /_/ /  / /    /  __/        / __/     / /   / / / // /_/ /  / / / // /__  /  __/
 *    /_____/\____/ \__,_/  |___/  \___/ /_/     \__/  \__,_/  /_/     \___/        /_/       /_/   /_/ /_/ \__,_/  /_/ /_/ \___/  \___/ 
 *                              
 
 *
 *    Web:      https://www.louverture.finance/
 *    Telegram: https://t.me/louverture_fi
 *    Discord:  https://discord.gg/HKjuqjdN
 *    Twitter:  https://twitter.com/louverture_fi
 *
 *    Created with Love by the DevTheApe.eth Team 
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import '../../libs/SafeMathInt.sol';
import '../../libs/SafeMathUint.sol';

library IterableMapping {
    // Iterable mapping from address to uint;
    struct Map {
        address[] keys;
        mapping(address => uint256) values;
        mapping(address => uint256) indexOf;
        mapping(address => bool) inserted;
    }

    function get(Map storage map, address key) public view returns (uint256) {
        return map.values[key];
    }

    function getIndexOfKey(Map storage map, address key) public view returns (int256) {
        if (!map.inserted[key]) {
            return -1;
        }
        return int256(map.indexOf[key]);
    }

    function getKeyAtIndex(Map storage map, uint256 index) public view returns (address) {
        return map.keys[index];
    }

    function size(Map storage map) public view returns (uint256) {
        return map.keys.length;
    }

    function set(
        Map storage map,
        address key,
        uint256 val
    ) public {
        if (map.inserted[key]) {
            map.values[key] = val;
        } else {
            map.inserted[key] = true;
            map.values[key] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
        }
    }

    function remove(Map storage map, address key) public {
        if (!map.inserted[key]) {
            return;
        }

        delete map.inserted[key];
        delete map.values[key];

        uint256 index = map.indexOf[key];
        uint256 lastIndex = map.keys.length - 1;
        address lastKey = map.keys[lastIndex];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }
}

/**
 * @title PaymentSplitter
 * @dev This contract allows to split Ether payments among a group of accounts. The sender does not need to be aware
 * that the Ether will be split in this way, since it is handled transparently by the contract.
 *
 * The split can be in equal parts or in any other arbitrary proportion. The way this is specified is by assigning each
 * account to a number of shares. Of all the Ether that this contract receives, each account will then be able to claim
 * an amount proportional to the percentage of total shares they were assigned.
 *
 * `PaymentSplitter` follows a _pull payment_ model. This means that payments are not automatically forwarded to the
 * accounts but kept in this contract, and the actual transfer is triggered as a separate step by calling the {release}
 * function.
 *
 * NOTE: This contract assumes that ERC20 tokens will behave similarly to native tokens (Ether). Rebasing tokens, and
 * tokens that apply fees during transfers, are likely to not be supported as expected. If in doubt, we encourage you
 * to run tests before sending real value to this contract.
 */
contract PaymentSplitter is Context {
    event PayeeAdded(address account, uint256 shares);
    event PaymentReleased(address to, uint256 amount);
    event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);
    event PaymentReceived(address from, uint256 amount);

    uint256 private _totalShares;
    uint256 private _totalReleased;

    mapping(address => uint256) private _shares;
    mapping(address => uint256) private _released;
    address[] private _payees;

    mapping(IERC20 => uint256) private _erc20TotalReleased;
    mapping(IERC20 => mapping(address => uint256)) private _erc20Released;

    /**
     * @dev Creates an instance of `PaymentSplitter` where each account in `payees` is assigned the number of shares at
     * the matching position in the `shares` array.
     *
     * All addresses in `payees` must be non-zero. Both arrays must have the same non-zero length, and there must be no
     * duplicates in `payees`.
     */
    constructor(address[] memory payees, uint256[] memory shares_) payable {
        require(payees.length == shares_.length, 'PaymentSplitter: payees and shares length mismatch');
        require(payees.length > 0, 'PaymentSplitter: no payees');

        for (uint256 i< payees.length; i++) {
            _addPayee(payees[i], shares_[i]);
        }
    }

    /**
     * @dev The Ether received will be logged with {PaymentReceived} events. Note that these events are not fully
     * reliable: it's possible for a contract to receive Ether without triggering this function. This only affects the
     * reliability of the events, and not the actual splitting of Ether.
     *
     * To learn more about this see the Solidity documentation for
     * https://solidity.readthedocs.io/en/latest/contracts.html#fallback-function[fallback
     * functions].
     */
    receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }

    /**
     * @dev Getter for the total shares held by payees.
     */
    function totalShares() public view returns (uint256) {
        return _totalShares;
    }

    /**
     * @dev Getter for the total amount of Ether already released.
     */
    function totalReleased() public view returns (uint256) {
        return _totalReleased;
    }

    /**
     * @dev Getter for the total amount of `token` already released. `token` should be the address of an IERC20
     * contract.
     */
    function totalReleased(IERC20 token) public view returns (uint256) {
        return _erc20TotalReleased[token];
    }

    /**
     * @dev Getter for the amount of shares held by an account.
     */
    function shares(address account) public view returns (uint256) {
        return _shares[account];
    }

    /**
     * @dev Getter for the amount of Ether already released to a payee.
     */
    function released(address account) public view returns (uint256) {
        return _released[account];
    }

    /**
     * @dev Getter for the amount of `token` tokens already released to a payee. `token` should be the address of an
     * IERC20 contract.
     */
    function released(IERC20 token, address account) public view returns (uint256) {
        return _erc20Released[token][account];
    }

    /**
     * @dev Getter for the address of the payee number `index`.
     */
    function payee(uint256 index) public view returns (address) {
        return _payees[index];
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of Ether they are owed, according to their percentage of the
     * total shares and their previous withdrawals.
     */
    function release(address payable account) public virtual {
        require(_shares[account] > 0, 'PaymentSplitter: account has no shares');

        uint256 totalReceived = address(this).balance + totalReleased();
        uint256 payment = _pendingPayment(account, totalReceived, released(account));

        require(payment != 0, 'PaymentSplitter: account is not due payment');

        _released[account] += payment;
        _totalReleased += payment;

        Address.sendValue(account, payment);
        emit PaymentReleased(account, payment);
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
     * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
     * contract.
     */
    function release(IERC20 token, address account) public virtual {
        require(_shares[account] > 0, 'PaymentSplitter: account has no shares');

        uint256 totalReceived = token.balanceOf(address(this)) + totalReleased(token);
        uint256 payment = _pendingPayment(account, totalReceived, released(token, account));

        require(payment != 0, 'PaymentSplitter: account is not due payment');

        _erc20Released[token][account] += payment;
        _erc20TotalReleased[token] += payment;

        SafeERC20.safeTransfer(token, account, payment);
        emit ERC20PaymentReleased(token, account, payment);
    }

    /**
     * @dev internal logic for computing the pending payment of an `account` given the token historical balances and
     * already released amounts.
     */
    function _pendingPayment(
        address account,
        uint256 totalReceived,
        uint256 alreadyReleased
    ) private view returns (uint256) {
        return (totalReceived * _shares[account]) / _totalShares - alreadyReleased;
    }

    /**
     * @dev Add a new payee to the contract.
     * @param account The address of the payee to add.
     * @param shares_ The number of shares owned by the payee.
     */
    function _addPayee(address account, uint256 shares_) private {
        require(account != address(0), 'PaymentSplitter: account is the zero address');
        require(shares_ > 0, 'PaymentSplitter: shares are 0');
        require(_shares[account] == 0, 'PaymentSplitter: account already has shares');

        _payees.push(account);
        _shares[account] = shares_;
        _totalShares = _totalShares + shares_;
        emit PayeeAdded(account, shares_);
    }
}

contract NODERewardManagement {
    using SafeMath for uint256;
    using IterableMapping for IterableMapping.Map;

    struct NodeEntity {
        string name;
        uint256 creationTime;
        uint256 lastClaimTime;
        uint256 rewardMult;
        uint256 nodeValue;
        uint256 rewardAvailable;
        uint256 addValueCount;
    }

    IterableMapping.Map private nodeOwners;
    mapping(address => NodeEntity[]) private _nodesOfUser;

    uint256 public nodeMinPrice;
    uint256 public rewardPerValue;
    uint256 public claimTime;

    address public gateKeeper;
    address public token;

    bool public autoDistri = true;
    bool public distribution = false;

    uint256 public gasForDistribution = 300000;
    uint256 public lastDistributionCount = 0;
    uint256 public lastIndexProcessed = 0;

    uint256[] public tierLevel = [100000, 105000, 110000, 120000, 130000, 140000];
    uint256[] public tierSlope = [1000, 500, 100, 50, 10, 0];

    uint256 public totalNodesCreated = 0;
    uint256 public totalRewardStaked = 0;

    constructor(
        uint256 _nodeMinPrice,
        uint256 _rewardPerValue,
        uint256 _claimTime
    ) {
        nodeMinPrice = _nodeMinPrice;
        rewardPerValue = _rewardPerValue;
        claimTime = _claimTime;
        gateKeeper = msg.sender;
    }

    modifier onlySentry() {
        require(msg.sender == token || msg.sender == gateKeeper, 'Fuck off');
        _;
    }

    function setToken(address token_) external onlySentry {
        token = token_;
    }

    function distributeRewards(uint256 gas, uint256 rewardValue)
        private
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        distribution = true;
        uint256 numberOfnodeOwners = nodeOwners.keys.length;
        require(numberOfnodeOwners > 0, 'DISTRI REWARDS: NO NODE OWNERS');
        if (numberOfnodeOwners == 0) {
            return (0, 0, lastIndexProcessed);
        }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();
        uint256 newGasLeft;
        uint256 localLastIndex = lastIndexProcessed;
        uint256 iterations = 0;
        uint256 newClaimTime = block.timestamp;
        uint256 nodesCount;
        uint256 claims = 0;
        NodeEntity[] storage nodes;
        NodeEntity storage _node;

        while (gasUsed < gas && iterations < numberOfnodeOwners) {
            localLastIndex++;
            if (localLastIndex >= nodeOwners.keys.length) {
                localLastIndex = 0;
            }
            nodes = _nodesOfUser[nodeOwners.keys[localLastIndex]];
            nodesCount = nodes.length;
            for (uint256 i< nodesCount; i++) {
                _node = nodes[i];
                if (claimable(_node)) {
                    _node.rewardAvailable += rewardValue;
                    _node.lastClaimTime = newClaimTime;
                    totalRewardStaked += rewardValue;
                    claims++;
                }
            }
            iterations++;

            newGasLeft = gasleft();

            if (gasLeft > newGasLeft) {
                gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
            }

            gasLeft = newGasLeft;
        }
        lastIndexProcessed = localLastIndex;
        distribution = false;
        return (iterations, claims, lastIndexProcessed);
    }

    function createNode(
        address account,
        string memory nodeName,
        uint256 _nodeInitialValue
    ) external onlySentry {
        require(isNameAvailable(account, nodeName), 'CREATE NODE: Name not available');
        _nodesOfUser[account].push(
            NodeEntity({
                name: nodeName,
                creationTime: block.timestamp,
                lastClaimTime: block.timestamp,
                rewardMult: 100000,
                nodeValue: _nodeInitialValue,
                addValueCount: 0,
                rewardAvailable: rewardPerValue
            })
        );
        nodeOwners.set(account, _nodesOfUser[account].length);
        totalNodesCreated++;
        if (autoDistri && !distribution) {
            distributeRewards(gasForDistribution, rewardPerValue);
        }
    }

    function isNameAvailable(address account, string memory nodeName) private view returns (bool) {
        NodeEntity[] memory nodes = _nodesOfUser[account];
        for (uint256 i< nodes.length; i++) {
            if (keccak256(bytes(nodes[i].name)) == keccak256(bytes(nodeName))) {
                return false;
            }
        }
        return true;
    }

    function _burn(uint256 index) internal {
        require(index < nodeOwners.size());
        nodeOwners.remove(nodeOwners.getKeyAtIndex(index));
    }

    function _getNodeWithCreatime(NodeEntity[] storage nodes, uint256 _creationTime) private view returns (NodeEntity storage) {
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, 'CASHOUT ERROR: You don not have nodes to cash-out');
        bool found = false;
        int256 index = binary_search(nodes, 0, numberOfNodes, _creationTime);
        uint256 validIndex;
        if (index >= 0) {
            found = true;
            validIndex = uint256(index);
        }
        require(found, 'NODE SEARCH: No NODE Found with this blocktime');
        return nodes[validIndex];
    }

    function binary_search(
        NodeEntity[] memory arr,
        uint256 low,
        uint256 high,
        uint256 x
    ) private view returns (int256) {
        if (high >= low) {
            uint256 mid = (high + low).div(2);
            if (arr[mid].creationTime == x) {
                return int256(mid);
            } else if (arr[mid].creationTime > x) {
                return binary_search(arr, low, mid - 1, x);
            } else {
                return binary_search(arr, mid + 1, high, x);
            }
        } else {
            return -1;
        }
    }

    function _cashoutNodeReward(address account, uint256 _creationTime) external onlySentry returns (uint256) {
        require(_creationTime > 0, 'NODE: CREATIME must be higher than zero');
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, 'CASHOUT ERROR: You don not have nodes to cash-out');
        NodeEntity storage node = _getNodeWithCreatime(nodes, _creationTime);
        uint256 rewardNode = node.rewardAvailable.mul(node.rewardMult).mul(node.nodeValue).div(100000).div(1e18);
        node.rewardAvailable = 0;
        node.rewardMult = 100000;
        node.addValueCount = 0;
        return rewardNode;
    }

    function _cashoutAllNodesReward(address account) external onlySentry returns (uint256) {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        require(nodesCount > 0, 'NODE: CREATIME must be higher than zero');
        NodeEntity storage _node;
        uint256 rewardsTotal = 0;
        for (uint256 i< nodesCount; i++) {
            _node = nodes[i];
            rewardsTotal += _node.rewardAvailable.mul(_node.rewardMult).mul(_node.nodeValue).div(100000).div(1e18);
            _node.rewardAvailable = 0;
            _node.rewardMult = 100000;
            _node.addValueCount = 0;
        }
        return rewardsTotal;
    }

    function _addNodeValue(address account, uint256 _creationTime) external onlySentry returns (uint256) {
        require(_creationTime > 0, 'NODE: CREATIME must be higher than zero');
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, 'CASHOUT ERROR: You don not have nodes to cash-out');
        NodeEntity storage node = _getNodeWithCreatime(nodes, _creationTime);
        uint256 rewardNode = node.rewardAvailable.mul(node.rewardMult).mul(node.nodeValue).div(100000).div(1e18);
        node.nodeValue += rewardNode;
        uint256 prevMult = node.rewardMult;
        if (rewardNode > 0) {
            if (prevMult >= tierLevel[5]) {
                node.rewardMult += tierSlope[5];
            } else if (prevMult >= tierLevel[4]) {
                node.rewardMult += tierSlope[4];
            } else if (prevMult >= tierLevel[3]) {
                node.rewardMult += tierSlope[2];
            } else if (prevMult >= tierLevel[2]) {
                node.rewardMult += tierSlope[2];
            } else if (prevMult >= tierLevel[1]) {
                node.rewardMult += tierSlope[1];
            } else {
                node.rewardMult += tierSlope[0];
            }

            node.rewardAvailable = 0;
            node.addValueCount += 1;
        }
        return rewardNode;
    }

    function _addAllNodeValue(address account) external onlySentry returns (uint256) {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        require(nodesCount > 0, 'NODE: CREATIME must be higher than zero');
        NodeEntity storage _node;
        uint256 rewardsTotal = 0;
        for (uint256 i< nodesCount; i++) {
            _node = nodes[i];
            rewardsTotal += _node.rewardAvailable.mul(_node.rewardMult).mul(_node.nodeValue).div(100000).div(1e18);
            _node.nodeValue += _node.rewardAvailable.mul(_node.rewardMult).mul(_node.nodeValue).div(100000).div(1e18);
            uint256 prevMult = _node.rewardMult;
            if (_node.rewardAvailable > 0) {
                if (prevMult >= tierLevel[5]) {
                    _node.rewardMult += tierSlope[5];
                } else if (prevMult >= tierLevel[4]) {
                    _node.rewardMult += tierSlope[4];
                } else if (prevMult >= tierLevel[3]) {
                    _node.rewardMult += tierSlope[2];
                } else if (prevMult >= tierLevel[2]) {
                    _node.rewardMult += tierSlope[2];
                } else if (prevMult >= tierLevel[1]) {
                    _node.rewardMult += tierSlope[1];
                } else {
                    _node.rewardMult += tierSlope[0];
                }
                _node.rewardAvailable = 0;
                _node.addValueCount += 1;
            }
        }
        return rewardsTotal;
    }

    function claimable(NodeEntity memory node) private view returns (bool) {
        return node.lastClaimTime + claimTime <= block.timestamp;
    }

    function _getNodeValueOf(address account) external view returns (uint256) {
        require(isNodeOwner(account), 'GET REWARD OF: NO NODE OWNER');
        uint256 nodesCount;
        uint256 valueCount = 0;

        NodeEntity[] storage nodes = _nodesOfUser[account];
        nodesCount = nodes.length;

        for (uint256 i< nodesCount; i++) {
            valueCount += nodes[i].nodeValue;
        }

        return valueCount;
    }

    function _getNodeValueOf(address account, uint256 _creationTime) external view returns (uint256) {
        require(isNodeOwner(account), 'GET REWARD OF: NO NODE OWNER');

        require(_creationTime > 0, 'NODE: CREATIME must be higher than zero');
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, 'CASHOUT ERROR: You don not have nodes to cash-out');
        NodeEntity storage node = _getNodeWithCreatime(nodes, _creationTime);
        uint256 valueNode = node.nodeValue;
        return valueNode;
    }

    function _getNodeValueAmountOf(address account, uint256 creationTime) external view returns (uint256) {
        return _getNodeWithCreatime(_nodesOfUser[account], creationTime).nodeValue;
    }

    function _getAddValueCountOf(address account, uint256 _creationTime) external view returns (uint256) {
        require(isNodeOwner(account), 'GET REWARD OF: NO NODE OWNER');

        require(_creationTime > 0, 'NODE: CREATIME must be higher than zero');
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, 'CASHOUT ERROR: You don not have nodes to cash-out');
        NodeEntity storage node = _getNodeWithCreatime(nodes, _creationTime);
        uint256 valueNode = node.addValueCount;
        return valueNode;
    }

    function _getRewardMultOf(address account) external view returns (uint256) {
        require(isNodeOwner(account), 'GET REWARD OF: NO NODE OWNER');
        uint256 nodesCount;
        uint256 valueCount = 0;
        uint256 totalCount = 0;
        uint256 rewardMult;

        NodeEntity[] storage nodes = _nodesOfUser[account];
        nodesCount = nodes.length;

        for (uint256 i< nodesCount; i++) {
            totalCount += nodes[i].nodeValue.mul(nodes[i].rewardMult);
            valueCount += nodes[i].nodeValue;
        }

        rewardMult = totalCount.div(valueCount);

        return rewardMult;
    }

    function _getRewardMultOf(address account, uint256 _creationTime) external view returns (uint256) {
        require(isNodeOwner(account), 'GET REWARD OF: NO NODE OWNER');

        require(_creationTime > 0, 'NODE: CREATIME must be higher than zero');
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, 'CASHOUT ERROR: You don not have nodes to cash-out');
        NodeEntity storage node = _getNodeWithCreatime(nodes, _creationTime);
        uint256 valueNode = node.rewardMult;
        return valueNode;
    }

    function _getRewardMultAmountOf(address account, uint256 creationTime) external view returns (uint256) {
        return _getNodeWithCreatime(_nodesOfUser[account], creationTime).rewardMult;
    }

    function _getRewardAmountOf(address account) external view returns (uint256) {
        require(isNodeOwner(account), 'GET REWARD OF: NO NODE OWNER');
        uint256 nodesCount;
        uint256 rewardCount = 0;

        NodeEntity[] storage nodes = _nodesOfUser[account];
        nodesCount = nodes.length;

        for (uint256 i< nodesCount; i++) {
            rewardCount += nodes[i].rewardAvailable.mul(nodes[i].rewardMult).mul(nodes[i].nodeValue).div(100000).div(1e18);
        }

        return rewardCount;
    }

    function _getRewardAmountOf(address account, uint256 _creationTime) external view returns (uint256) {
        require(isNodeOwner(account), 'GET REWARD OF: NO NODE OWNER');

        require(_creationTime > 0, 'NODE: CREATIME must be higher than zero');
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, 'CASHOUT ERROR: You don not have nodes to cash-out');
        NodeEntity storage node = _getNodeWithCreatime(nodes, _creationTime);
        uint256 rewardNode = node.rewardAvailable.mul(node.rewardMult).mul(node.nodeValue).div(100000).div(1e18);
        return rewardNode;
    }

    function _getNodeRewardAmountOf(address account, uint256 creationTime) external view returns (uint256) {
        return
            _getNodeWithCreatime(_nodesOfUser[account], creationTime)
                .rewardAvailable
                .mul(_getNodeWithCreatime(_nodesOfUser[account], creationTime).rewardMult)
                .mul(_getNodeWithCreatime(_nodesOfUser[account], creationTime).nodeValue)
                .div(100000)
                .div(1e18);
    }

    function _getNodesNames(address account) external view returns (string memory) {
        require(isNodeOwner(account), 'GET NAMES: NO NODE OWNER');
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory names = nodes[0].name;
        string memory separator = '#';
        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            names = string(abi.encodePacked(names, separator, _node.name));
        }
        return names;
    }

    function _getNodesCreationTime(address account) external view returns (string memory) {
        require(isNodeOwner(account), 'GET CREATIME: NO NODE OWNER');
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _creationTimes = uint2str(nodes[0].creationTime);
        string memory separator = '#';

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _creationTimes = string(abi.encodePacked(_creationTimes, separator, uint2str(_node.creationTime)));
        }
        return _creationTimes;
    }

    function _getNodesRewardAvailable(address account) external view returns (string memory) {
        require(isNodeOwner(account), 'GET REWARD: NO NODE OWNER');
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _rewardsAvailable = uint2str(
            nodes[0].rewardAvailable.mul(nodes[0].rewardMult).mul(nodes[0].nodeValue).div(100000).div(1e18)
        );
        string memory separator = '#';

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            uint256 _totalReward = _node.rewardAvailable.mul(_node.rewardMult).mul(_node.nodeValue).div(100000).div(1e18);
            _rewardsAvailable = string(abi.encodePacked(_rewardsAvailable, separator, uint2str(_totalReward)));
        }
        return _rewardsAvailable;
    }

    function _getNodesLastClaimTime(address account) external view returns (string memory) {
        require(isNodeOwner(account), 'LAST CLAIME TIME: NO NODE OWNER');
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _lastClaimTimes = uint2str(nodes[0].lastClaimTime);
        string memory separator = '#';

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _lastClaimTimes = string(abi.encodePacked(_lastClaimTimes, separator, uint2str(_node.lastClaimTime)));
        }
        return _lastClaimTimes;
    }

    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return '0';
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function _changeNodeMinPrice(uint256 newNodeMinPrice) external onlySentry {
        nodeMinPrice = newNodeMinPrice;
    }

    function _changeRewardPerValue(uint256 newPrice) external onlySentry {
        rewardPerValue = newPrice;
    }

    function _changeClaimTime(uint256 newTime) external onlySentry {
        claimTime = newTime;
    }

    function _changeAutoDistri(bool newMode) external onlySentry {
        autoDistri = newMode;
    }

    function _changeTierSystem(uint256[] memory newTierLevel, uint256[] memory newTierSlope) external onlySentry {
        tierLevel = newTierLevel;
        tierSlope = newTierSlope;
    }

    function _changeGasDistri(uint256 newGasDistri) external onlySentry {
        gasForDistribution = newGasDistri;
    }

    function _getNodeNumberOf(address account) public view returns (uint256) {
        return nodeOwners.get(account);
    }

    function isNodeOwner(address account) private view returns (bool) {
        return nodeOwners.get(account) > 0;
    }

    function _isNodeOwner(address account) external view returns (bool) {
        return isNodeOwner(account);
    }

    function _distributeRewards()
        external
        onlySentry
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return distributeRewards(gasForDistribution, rewardPerValue);
    }
}

contract LVT is ERC20, Ownable, PaymentSplitter {
    using SafeMath for uint256;

    NODERewardManagement public nodeRewardManager;

    IUniswapV2Router02 public uniswapV2Router;

    address public uniswapV2Pair;
    address public futurUsePool;
    address public distributionPool;
    address public devPool;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    uint256 public rewardsFee;
    uint256 public liquidityPoolFee;
    uint256 public futurFee;
    uint256 public totalFees;

    uint256 public cashoutFee;

    uint256 private rwSwap;
    uint256 private devShare;
    bool private swapping = false;
    bool private swapLiquify = true;
    uint256 public swapTokensAmount;

    bool private tradingOpen = false;
    uint256 private snipeBlockAmt;
    uint256 private _openTradingBlock = 0;
    uint256 private maxTx = 1;

    mapping(address => bool) public _isBlacklisted;
    mapping(address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);

    constructor(
        address[] memory payees,
        uint256[] memory shares,
        address[] memory addresses,
        uint256[] memory balances,
        address uniV2Router,
        uint256 snipeBlkAmt
    ) ERC20('Louverture', 'LVT') PaymentSplitter(payees, shares) {
        futurUsePool = addresses[4];
        distributionPool = addresses[5];
        devPool = addresses[6];
        snipeBlockAmt = snipeBlkAmt;

        require(
            futurUsePool != address(0) && distributionPool != address(0) && devPool != address(0),
            'FUTUR, DEV & REWARD ADDRESS CANNOT BE ZERO'
        );

        require(uniV2Router != address(0), 'ROUTER CANNOT BE ZERO');
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(uniV2Router);

        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        futurFee = 20;
        rewardsFee = 70;
        liquidityPoolFee = 10;
        cashoutFee = 10;
        rwSwap = 20;
        devShare = 50;

        totalFees = rewardsFee.add(liquidityPoolFee).add(futurFee);

        require(addresses.length > 0 && balances.length > 0, 'CONSTR: addresses array length must be greater than zero');
        require(addresses.length == balances.length, 'CONSTR: addresses arrays length mismatch');

        for (uint256 i< addresses.length; i++) {
            _mint(addresses[i], balances[i] * (10**18));
        }
        require(totalSupply() == 1000000000e18, 'CONSTR: totalSupply must equal 1 billion');
        swapTokensAmount = 500 * (10**18);
    }

    function setNodeManagement(address nodeManagement) external onlyOwner {
        nodeRewardManager = NODERewardManagement(nodeManagement);
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), 'TKN: The router already has that address');
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function updateSwapTokensAmount(uint256 newVal) external onlyOwner {
        swapTokensAmount = newVal;
    }

    function updateFuturWall(address payable wall) external onlyOwner {
        futurUsePool = wall;
    }

    function updateDevWall(address payable wall) external onlyOwner {
        devPool = wall;
    }

    function updateRewardsWall(address payable wall) external onlyOwner {
        distributionPool = wall;
    }

    function updateRewardsFee(uint256 value) external onlyOwner {
        rewardsFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(futurFee);
    }

    function updateLiquiditFee(uint256 value) external onlyOwner {
        liquidityPoolFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(futurFee);
    }

    function updateFuturFee(uint256 value) external onlyOwner {
        futurFee = value;
        totalFees = rewardsFee.add(liquidityPoolFee).add(futurFee);
    }

    function updateCashoutFee(uint256 value) external onlyOwner {
        cashoutFee = value;
    }

    function updateRwSwapFee(uint256 value) external onlyOwner {
        rwSwap = value;
    }

    function updateDevShare(uint256 value) external onlyOwner {
        devShare = value;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, 'TKN: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs');

        _setAutomatedMarketMakerPair(pair, value);
    }

    function blacklistMalicious(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, 'TKN: Automated market maker pair is already set to that value');
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], 'Blacklisted address');
        require(from != address(0), 'ERC20: transfer from the zero address');
        require(to != address(0), 'ERC20: transfer to the zero address');
        if (from != owner() && to != uniswapV2Pair && to != address(uniswapV2Router) && to != address(this) && from != address(this)) {
            require(tradingOpen, 'Trading not yet enabled.');

            // anti whale
            if (
                to != futurUsePool &&
                to != distributionPool &&
                to != devPool &&
                from != futurUsePool &&
                from != distributionPool &&
                from != devPool
            ) {
                uint256 totalSupply = totalSupply();
                uint256 walletBalance = balanceOf(address(to));
                require(
                    amount.add(walletBalance) <= totalSupply.mul(maxTx).div(10000),
                    'STOP TRYING TO BECOME A WHALE. WE KNOW WHO YOU ARE.'
                );
            }
        }
        super._transfer(from, to, amount);
    }

    function swapAndSendToFee(address destination, uint256 tokens) private {
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBalance = (address(this).balance).sub(initialETHBalance);
        payable(destination).transfer(newBalance);
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{ value: ethAmount }(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

    function createNodeWithTokens(string memory name, uint256 _initValue) public {
        require(bytes(name).length > 3 && bytes(name).length < 32, 'NODE CREATION: NAME SIZE INVALID');
        address sender = _msgSender();
        require(sender != address(0), 'NODE CREATION:  creation from the zero address');
        require(!_isBlacklisted[sender], 'NODE CREATION: Blacklisted address');
        require(
            sender != futurUsePool && sender != distributionPool && sender != devPool,
            'NODE CREATION: futur, dev and rewardsPool cannot create node'
        );

        uint256 nodeMinPrice = nodeRewardManager.nodeMinPrice();
        uint256 nodePrice = _initValue;
        require(nodePrice >= nodeMinPrice, 'NODE CREATION: Node Value set below nodeMinPrice');
        require(balanceOf(sender) >= nodePrice.mul(1e18), 'NODE CREATION: Balance too low for creation. Use lower initValue');
        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (swapAmountOk && swapLiquify && !swapping && sender != owner() && !automatedMarketMakerPairs[sender]) {
            swapping = true;

            uint256 fdTokens = contractTokenBalance.mul(futurFee).div(100);
            uint256 devTokens = fdTokens.mul(devShare).div(100);
            uint256 futurTokens = fdTokens.sub(devTokens);

            swapAndSendToFee(devPool, devTokens);
            swapAndSendToFee(futurUsePool, futurTokens);

            uint256 rewardsPoolTokens = contractTokenBalance.mul(rewardsFee).div(100);

            uint256 rewardsTokenstoSwap = rewardsPoolTokens.mul(rwSwap).div(100);

            swapAndSendToFee(distributionPool, rewardsTokenstoSwap);
            super._transfer(address(this), distributionPool, rewardsPoolTokens.sub(rewardsTokenstoSwap));

            uint256 swapTokens = contractTokenBalance.mul(liquidityPoolFee).div(100);

            swapAndLiquify(swapTokens);

            swapTokensForEth(balanceOf(address(this)));

            swapping = false;
        }
        super._transfer(sender, address(this), nodePrice.mul(1e18));
        nodeRewardManager.createNode(sender, name, _initValue.mul(1e18));
    }

    function cashoutReward(uint256 blocktime) public {
        address sender = _msgSender();
        require(sender != address(0), 'CSHT:  creation from the zero address');
        require(!_isBlacklisted[sender], 'MANIA CSHT: Blacklisted address');
        require(sender != futurUsePool && sender != distributionPool, 'CSHT: futur and rewardsPool cannot cashout rewards');
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender, blocktime);
        require(rewardAmount > 0, 'CSHT: You don not have enough reward to cash out');

        if (swapLiquify) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = rewardAmount.mul(cashoutFee).div(100);
                swapAndSendToFee(futurUsePool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManager._cashoutNodeReward(sender, blocktime);
    }

    function cashoutAll() public {
        address sender = _msgSender();
        require(sender != address(0), 'MANIA CSHT:  creation from the zero address');
        require(!_isBlacklisted[sender], 'MANIA CSHT: Blacklisted address');
        require(sender != futurUsePool && sender != distributionPool, 'MANIA CSHT: futur and rewardsPool cannot cashout rewards');
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender);
        require(rewardAmount > 0, 'MANIA CSHT: You don not have enough reward to cash out');
        if (swapLiquify) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = rewardAmount.mul(cashoutFee).div(100);
                swapAndSendToFee(futurUsePool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManager._cashoutAllNodesReward(sender);
    }

    function addNodeValue(uint256 blocktime) public {
        address sender = _msgSender();
        require(sender != address(0), 'CSHT:  creation from the zero address');
        require(!_isBlacklisted[sender], 'MANIA CSHT: Blacklisted address');
        require(
            sender != futurUsePool && sender != distributionPool && sender != devPool,
            'CSHT: futur, dev and rewardsPool cannot compound nodes'
        );
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender, blocktime);
        require(rewardAmount > 0, 'CSHT: You don not have enough reward to compound your node');

        if (swapLiquify) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = rewardAmount.mul(cashoutFee).div(100);
                swapAndSendToFee(devPool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }

        super._transfer(distributionPool, address(this), rewardAmount);
        nodeRewardManager._addNodeValue(sender, blocktime);
    }

    function addAllNodeValue() public {
        address sender = _msgSender();
        require(sender != address(0), 'MANIA CSHT:  creation from the zero address');
        require(!_isBlacklisted[sender], 'MANIA CSHT: Blacklisted address');
        require(
            sender != futurUsePool && sender != distributionPool && sender != devPool,
            'MANIA CSHT: futur, dev and rewardsPool cannot cashout rewards'
        );
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender);
        require(rewardAmount > 0, 'MANIA CSHT: You don not have enough reward to compound');
        if (swapLiquify) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = rewardAmount.mul(cashoutFee).div(100);
                swapAndSendToFee(devPool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
        super._transfer(distributionPool, address(this), rewardAmount);
        nodeRewardManager._addAllNodeValue(sender);
    }

    function getNodeMultiplier(uint256 blocktime) public view returns (uint256) {
        return nodeRewardManager._getRewardMultOf(_msgSender(), blocktime);
    }

    function getNodeMultiplierOf(address account, uint256 blocktime) public view returns (uint256) {
        return nodeRewardManager._getRewardMultOf(account, blocktime);
    }

    function getNodeValue(uint256 blocktime) public view returns (uint256) {
        return nodeRewardManager._getNodeValueOf(_msgSender(), blocktime);
    }

    function getNodeValueOf(address account, uint256 blocktime) public view returns (uint256) {
        return nodeRewardManager._getNodeValueOf(account, blocktime);
    }

    function getAllNodeValue() public view returns (uint256) {
        return nodeRewardManager._getNodeValueOf(_msgSender());
    }

    function getAllNodeValueOf(address account) public view returns (uint256) {
        return nodeRewardManager._getNodeValueOf(account);
    }

    function boostReward(uint256 amount) public onlyOwner {
        if (amount > address(this).balance) amount = address(this).balance;
        payable(owner()).transfer(amount);
    }

    function changeSwapLiquify(bool newVal) public onlyOwner {
        swapLiquify = newVal;
    }

    function getNodeNumberOf(address account) public view returns (uint256) {
        return nodeRewardManager._getNodeNumberOf(account);
    }

    function getRewardAmountOf(address account) public view onlyOwner returns (uint256) {
        return nodeRewardManager._getRewardAmountOf(account);
    }

    function getRewardAmount() public view returns (uint256) {
        require(_msgSender() != address(0), 'SENDER CAN NOT BE ZERO');
        require(nodeRewardManager._isNodeOwner(_msgSender()), 'NO NODE OWNER');
        return nodeRewardManager._getRewardAmountOf(_msgSender());
    }

    function changeNodeMinPrice(uint256 newNodeMinPrice) public onlyOwner {
        nodeRewardManager._changeNodeMinPrice(newNodeMinPrice);
    }

    function changeTierSystem(uint256[] memory newTierLevels, uint256[] memory newTierSlopes) public onlyOwner {
        require(newTierLevels.length == 6, 'newTierLevels length has to be 6');
        require(newTierSlopes.length == 6, 'newTierSlopes length has to be 6');
        nodeRewardManager._changeTierSystem(newTierLevels, newTierSlopes);
    }

    function getNodeMinPrice() public view returns (uint256) {
        return nodeRewardManager.nodeMinPrice();
    }

    function changeRewardPerValue(uint256 newPrice) public onlyOwner {
        nodeRewardManager._changeRewardPerValue(newPrice);
    }

    function getRewardPerValue() public view returns (uint256) {
        return nodeRewardManager.rewardPerValue();
    }

    function changeClaimTime(uint256 newTime) public onlyOwner {
        nodeRewardManager._changeClaimTime(newTime);
    }

    function getClaimTime() public view returns (uint256) {
        return nodeRewardManager.claimTime();
    }

    function changeAutoDistri(bool newMode) public onlyOwner {
        nodeRewardManager._changeAutoDistri(newMode);
    }

    function getAutoDistri() public view returns (bool) {
        return nodeRewardManager.autoDistri();
    }

    function changeGasDistri(uint256 newGasDistri) public onlyOwner {
        nodeRewardManager._changeGasDistri(newGasDistri);
    }

    function getGasDistri() public view returns (uint256) {
        return nodeRewardManager.gasForDistribution();
    }

    function getDistriCount() public view returns (uint256) {
        return nodeRewardManager.lastDistributionCount();
    }

    function getNodesNames() public view returns (string memory) {
        require(_msgSender() != address(0), 'SENDER CAN NOT BE ZERO');
        require(nodeRewardManager._isNodeOwner(_msgSender()), 'NO NODE OWNER');
        return nodeRewardManager._getNodesNames(_msgSender());
    }

    function getNodesCreatime() public view returns (string memory) {
        require(_msgSender() != address(0), 'SENDER CAN NOT BE ZERO');
        require(nodeRewardManager._isNodeOwner(_msgSender()), 'NO NODE OWNER');
        return nodeRewardManager._getNodesCreationTime(_msgSender());
    }

    function getNodesRewards() public view returns (string memory) {
        require(_msgSender() != address(0), 'SENDER CAN NOT BE ZERO');
        require(nodeRewardManager._isNodeOwner(_msgSender()), 'NO NODE OWNER');
        return nodeRewardManager._getNodesRewardAvailable(_msgSender());
    }

    function getNodesLastClaims() public view returns (string memory) {
        require(_msgSender() != address(0), 'SENDER CAN NOT BE ZERO');
        require(nodeRewardManager._isNodeOwner(_msgSender()), 'NO NODE OWNER');
        return nodeRewardManager._getNodesLastClaimTime(_msgSender());
    }

    function distributeRewards()
        public
        onlyOwner
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return nodeRewardManager._distributeRewards();
    }

    function publiDistriRewards() public {
        nodeRewardManager._distributeRewards();
    }

    function getTotalStakedReward() public view returns (uint256) {
        return nodeRewardManager.totalRewardStaked();
    }

    function getTotalCreatedNodes() public view returns (uint256) {
        return nodeRewardManager.totalNodesCreated();
    }

    function openTrading() external onlyOwner {
        require(!tradingOpen, 'trading is already open');
        tradingOpen = true;
        _openTradingBlock = block.number;
    }

    function updateMaxTxAmount(uint256 newVal) public onlyOwner {
        maxTx = newVal;
    }
}
