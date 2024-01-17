// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract Testsd is IERC20, Ownable {
    using SafeERC20 for IERC20;

    string private _name;
    string private _symbol;
    uint8 private _decimals = 18;

    mapping(address => uint256) private _reflections;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) public excludedFromFee;
    mapping(address => bool) public excludedFromReward;
    uint256 private _totalRatedBalance;
    uint256 private _totalRatedReflection;

    uint256 public totalFees;
    uint256 private _totalSupply;
    address private _router = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3; //router

    bool public BRN_ENABLED;
    bool public MRK_ENABLED;
    bool public REF_ENABLED;

    uint256 public taxFee;
    uint256 public liqFee;
    uint256 public brnFee;
    uint256 public mrkFee;
    uint256 public refFee;
    uint256 public feeLimit; // up to FLOAT_FACTOR / 2
    uint256 private constant FLOAT_FACTOR = 1e4;
    uint256 private constant MAX = type(uint256).max;

    IUniswapV2Router02 public swapRouter;
    mapping(address => bool) public swapPairs;
    address private swapWETH;

    bool private _liqInProgress;
    bool public liqStatus;
    uint256 private liqThreshold;
    uint256 public txLimit;
    address public liquidityAddress;
    address public marketingAddress;
    mapping(address => address) public referrers;
    mapping(address => address[]) public referrals;
    mapping(address => uint256) public referralsCount;

    address public factory;

    event UpdateFees(uint256 newTaxFee, uint256 newLiqFee, uint256 newBrnFee, uint256 newMrkFee, uint256 newRefFee);
    event UpdateTxLimit(uint256 newTxLimit);
    event UpdateLiqThreshold(uint256 newLiqThreshold);
    event UpdateLiqStatus(bool newLiqStatus);
    event UpdateLiquidityAddress(address newLiquidityAddress);
    event UpdateMarketingAddress(address newMarketingkAddress);
    event UpdateSwapRouter(address newRouter, address newPair);
    event LiquidityAdded(uint256 indexed tokensToLiqudity, uint256 indexed bnbToLiquidity);
    event ReferrerSet(address indexed referrer, address referral);
    event SwapPairUpdated(address indexed pair);
    event DistributionProceeds(uint256 amount);
    event ExcludedFromReward(address indexed account);
    event IncludedInReward(address indexed account);
    event ExcludedFromFee(address indexed account);
    event IncludedInFee(address indexed account);
    event RecoveredLockedTokens(address indexed token, address indexed receiver, uint256 amount);

    modifier lockTheSwap() {
        _liqInProgress = true;
        _;
        _liqInProgress = false;
    }

    /**
    * @param flags_ boolean parameters:
                    [0] burning fee on transfers, cannot be updated after creation
                    [1] marketing fee on transfers, cannot be updated after creation
                    [2] referrals fee on transfers, cannot be updated after creation
                    [3] autoLiquify flag, updatable by the owner after creation
    * @param feesAndLimits_ uint256 parameters:
                    [0] totalSupply, initial token amount in ether
                    [1] taxFee on transfers, updatable within limits after creation ??
                    [2] liquidityFee on transfers, updatable within limits after creation
                    [3] burnFee on transfers, only if _flags[0] is set
                    [4] marketingFee on transfers, only if _flags[1] is set
                    [5] referralFee on transfers, only if _flags[2] is set
                    [6] feeLimit of total fees, cannot be updated after creation
                    [7] liquidityThreshold, min amount of tokens to be swapped on transfers
                    [8] txLimit, max amount of transfer for non-privileged users
    * @param markAddr marketingAddress, only if _flags[1] is set
    */
    constructor(
        string memory name_,
        string memory symbol_,
        bool[4] memory flags_,
        uint256[9] memory feesAndLimits_,
        address markAddr
    ) {
        require(bytes(name_).length != 0, "Empty name");
        require(bytes(symbol_).length != 0, "Empty symbol");
        require(feesAndLimits_[0] != 0, "Zero total supply");
        require(_router != address(0), "Zero Router address");

        require(feesAndLimits_[6] <= FLOAT_FACTOR / 2, "Wrong limit");
        require(
            feesAndLimits_[1] + feesAndLimits_[2] + feesAndLimits_[3] + feesAndLimits_[4] + feesAndLimits_[5] <=
                feesAndLimits_[6],
            "Fees too high"
        );

        _name = name_;
        _symbol = symbol_;

        _totalSupply = feesAndLimits_[0];
        uint256 maxReflection = MAX / feesAndLimits_[0];
        _totalRatedBalance = feesAndLimits_[0];
        _totalRatedReflection = maxReflection;
        _reflections[owner()] = maxReflection;

        BRN_ENABLED = flags_[0];
        MRK_ENABLED = flags_[1];
        REF_ENABLED = flags_[2];

        taxFee = feesAndLimits_[1];
        liqFee = feesAndLimits_[2];
        liquidityAddress = owner();
        liqStatus = flags_[3];
        feeLimit = feesAndLimits_[6];

        if (flags_[0]) {
            brnFee = feesAndLimits_[3];
        }
        if (flags_[1]) {
            mrkFee = feesAndLimits_[4];
            marketingAddress = markAddr;
        }
        if (flags_[2]) {
            refFee = feesAndLimits_[5];
            if (!flags_[1]) marketingAddress = markAddr;
        }

        require(
            feesAndLimits_[8] >= feesAndLimits_[0] / FLOAT_FACTOR, // txLimit >= totalSupply/10000
            "txLimit is too low"
        );
        require(
            feesAndLimits_[8] <= feesAndLimits_[0], // txLimit <= totalSupply
            "txLimit is too high"
        );
        require(
            feesAndLimits_[7] <= feesAndLimits_[8], // liqThreshold <= txLimit
            "liqThreshold is too high"
        );
        txLimit = feesAndLimits_[8];
        liqThreshold = feesAndLimits_[7];

        address _weth = IUniswapV2Router02(_router).WETH();
        require(_weth != address(0), "Wrong router");
        swapWETH = _weth;
        address _swapPair = IUniswapV2Factory(IUniswapV2Router02(_router).factory()).createPair(address(this), _weth);
        _updateSwapPair(_swapPair);
        swapRouter = IUniswapV2Router02(_router);
        excludeFromReward(_swapPair);
        excludeFromFee(owner());

        transferOwnership(owner());
        emit Transfer(address(0), owner(), feesAndLimits_[0]);
        emit UpdateFees(feesAndLimits_[1], feesAndLimits_[2], feesAndLimits_[3], feesAndLimits_[4], feesAndLimits_[5]);
        emit UpdateTxLimit(feesAndLimits_[8]);
        emit UpdateLiqThreshold(feesAndLimits_[7]);
        emit UpdateLiqStatus(flags_[3]);
        emit UpdateLiquidityAddress(owner());
        emit UpdateMarketingAddress(markAddr);
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function getOwner() external view returns (address) {
        return owner();
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (excludedFromReward[account]) return _balances[account];
        (uint256 reflection, uint256 balance) = _getRate();
        return (_reflections[account] * balance) / reflection;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(address owner_, address spender, uint256 amount) private {
        require(owner_ != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        _transfer(sender, recipient, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    function distribute(uint256 amount) external {
        require(!excludedFromReward[msg.sender], "Not for excluded");
        (uint256 reflection, uint256 balance) = _getRate();
        uint256 rAmount = (amount * reflection) / balance;
        uint256 userBalance = _reflections[msg.sender];
        require(userBalance >= rAmount, "ERC20: transfer amount exceeds balance");
        _reflections[msg.sender] = userBalance - rAmount;
        _totalRatedReflection -= rAmount;
        totalFees += amount;

        emit DistributionProceeds(amount);
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!excludedFromReward[account], "Already excluded");

        uint256 currentReflection = _reflections[account];
        if (currentReflection > 0) {
            (uint256 reflection, uint256 balance) = _getRate();
            uint256 currentBalance = (currentReflection * balance) / reflection;
            _balances[account] = currentBalance;
            _totalRatedBalance -= currentBalance;
            _totalRatedReflection -= currentReflection;

            _reflections[account] = 0;
        }

        excludedFromReward[account] = true;

        emit ExcludedFromReward(account);
    }

    function includeInReward(address account) external onlyOwner {
        require(excludedFromReward[account], "Not excluded");

        uint256 currentBalance = _balances[account];
        if (currentBalance > 0) {
            (uint256 reflection, uint256 balance) = _getRate();
            uint256 currentReflection = (currentBalance * reflection) / balance;

            _totalRatedBalance += currentBalance;
            _totalRatedReflection += currentReflection;
            _reflections[account] = currentReflection;

            _balances[account] = 0;
        }

        excludedFromReward[account] = false;

        emit IncludedInReward(account);
    }

    function excludeFromFee(address account) public onlyOwner {
        require(!swapPairs[account], "Not for Pair address");
        excludedFromFee[account] = true;

        emit ExcludedFromFee(account);
    }

    function includeInFee(address account) external onlyOwner {
        delete excludedFromFee[account];

        emit IncludedInFee(account);
    }

    function setFee(
        uint256 newTaxFee,
        uint256 newLiqFee,
        uint256 newBrnFee,
        uint256 newMrkFee,
        uint256 newRefFee
    ) external onlyOwner {
        require(newTaxFee + newLiqFee + newBrnFee + newMrkFee + newRefFee <= feeLimit, "Fees too high");
        taxFee = newTaxFee;
        liqFee = newLiqFee;

        if (BRN_ENABLED) {
            brnFee = newBrnFee;
        }
        if (MRK_ENABLED) {
            mrkFee = newMrkFee;
        }
        if (REF_ENABLED) {
            refFee = newRefFee;
        }

        emit UpdateFees(newTaxFee, newLiqFee, brnFee, mrkFee, refFee);
    }

    function setLiquifyStatus(bool newStatus) external onlyOwner {
        liqStatus = newStatus;

        emit UpdateLiqStatus(newStatus);
    }

    function setLiquifyThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold <= txLimit, "Threshold exceeds txLimit");
        liqThreshold = newThreshold;

        emit UpdateLiqThreshold(newThreshold);
    }

    function setLiquidityAddress(address newLiquidityAddress) external onlyOwner {
        require(newLiquidityAddress != address(0), "zero address");
        liquidityAddress = newLiquidityAddress;

        emit UpdateLiquidityAddress(newLiquidityAddress);
    }

    function setMarketingAddress(address newMarketingAddress) external onlyOwner {
        require(MRK_ENABLED || REF_ENABLED, "Denied");
        require(newMarketingAddress != address(0), "Zero address");
        marketingAddress = newMarketingAddress;

        emit UpdateMarketingAddress(newMarketingAddress);
    }

    function setReferrer(address referrerAddress) external payable {
        require(REF_ENABLED, "Denied");
        require(referrerAddress != msg.sender, "Referrer not allowed");
        require(balanceOf(referrerAddress) > 0, "Referrer is not active");
        require(referrers[msg.sender] == address(0), "Referrer is not empty");
        require(msg.value >= 0.1 ether);
        referrers[msg.sender] = referrerAddress;
        referrals[referrerAddress].push(msg.sender);
        referralsCount[referrerAddress] += 1;
        payable(owner()).transfer(msg.value);
        emit ReferrerSet(referrerAddress, msg.sender);
    }

    function setTxLimit(uint256 newTxLimit) external onlyOwner {
        uint256 curTotalSupply = _totalSupply;
        require(newTxLimit >= liqThreshold, "txLimit is below liqThreshold");
        require(newTxLimit >= curTotalSupply / FLOAT_FACTOR, "txLimit is too low");
        require(newTxLimit <= curTotalSupply, "txLimit is too high");
        txLimit = newTxLimit;
        emit UpdateTxLimit(newTxLimit);
    }

    function setSwapRouter(IUniswapV2Router02 newRouter) external onlyOwner {
        address newPair = IUniswapV2Factory(newRouter.factory()).getPair(address(this), newRouter.WETH());
        require(newPair != address(0), "Pair does not exist");
        swapRouter = newRouter;
        _updateSwapPair(newPair);
        swapWETH = newRouter.WETH();
        require(swapWETH != address(0), "Wrong router");
        excludeFromReward(newPair);

        emit UpdateSwapRouter(address(newRouter), newPair);
    }

    function _updateSwapPair(address pair) internal {
        swapPairs[pair] = true;

        emit SwapPairUpdated(pair);
    }

    function _getRate() public view returns (uint256, uint256) {
        uint256 totalRatedBalance_ = _totalRatedBalance;

        if (totalRatedBalance_ == 0) {
            uint256 ___totalSupply = _totalSupply;
            return (MAX / ___totalSupply, ___totalSupply);
        }
        return (_totalRatedReflection, totalRatedBalance_);
    }

    function _takeLiquidity(uint256 amount, uint256 reflect, uint256 reflectBalance) private {
        uint256 rAmount = (amount * reflect) / reflectBalance;

        if (excludedFromReward[address(this)]) {
            _balances[address(this)] += amount;
            _totalRatedBalance -= amount;
            _totalRatedReflection -= rAmount;
            return;
        }
        _reflections[address(this)] += rAmount;
    }

    function _getFeeValues(
        uint256 amount,
        bool takeFee
    ) private view returns (uint256 _tax, uint256 _liq, uint256 _brn, uint256 _mrk, uint256 _ref) {
        if (takeFee) {
            _tax = (amount * taxFee) / FLOAT_FACTOR;
            _liq = (amount * liqFee) / FLOAT_FACTOR;
            if (BRN_ENABLED) _brn = (amount * brnFee) / FLOAT_FACTOR;
            if (MRK_ENABLED) _mrk = (amount * mrkFee) / FLOAT_FACTOR;
            if (REF_ENABLED) _ref = (amount * refFee) / FLOAT_FACTOR;
        }
    }

    function _reflectFee(
        address from,
        uint256 reflect,
        uint256 reflectBalance,
        uint256 tax,
        uint256 liq,
        uint256 brn,
        uint256 mrk,
        uint256 ref
    ) private returns (uint256) {
        _totalRatedReflection -= (tax * reflect) / reflectBalance;
        totalFees += tax;

        if (BRN_ENABLED && brn > 0) {
            _totalSupply -= brn;
            _totalRatedBalance -= brn;
            _totalRatedReflection -= (brn * reflect) / reflectBalance;
            emit Transfer(from, address(0), brn);
        }
        if (REF_ENABLED) {
            uint256 mrk_;
            if (MRK_ENABLED) mrk_ = mrk;
            address referrerAddress = referrers[tx.origin];
            if (referrerAddress == address(0)) {
                _takeFee(from, marketingAddress, mrk_ + ref, reflect, reflectBalance);
            } else {
                _takeFee(from, marketingAddress, mrk_, reflect, reflectBalance);
                _takeFee(from, referrerAddress, ref, reflect, reflectBalance);
            }
        } else if (MRK_ENABLED) {
            _takeFee(from, marketingAddress, mrk, reflect, reflectBalance);
        }

        return liq;
    }

    function _takeFee(
        address from,
        address recipient,
        uint256 amount,
        uint256 reflect,
        uint256 reflectBalance
    ) private {
        if (amount == 0) return;
        uint256 rAmount = (amount * reflect) / reflectBalance;

        emit Transfer(from, recipient, amount);

        if (excludedFromReward[recipient]) {
            _balances[recipient] += amount;
            _totalRatedBalance -= amount;
            _totalRatedReflection -= rAmount;
            return;
        }
        _reflections[recipient] += rAmount;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(to != address(0), "ERC20: transfer to the zero address");
        address owner_ = owner();
        if (from != owner_ && to != owner_) require(amount <= txLimit, "txLimit exceeded");

        uint256 _liqThreshold = liqThreshold;
        bool liquifyReady = (balanceOf(address(this)) >= _liqThreshold &&
            !_liqInProgress &&
            liqStatus &&
            !swapPairs[from]);
        if (liquifyReady) _swapAndLiquify(_liqThreshold);

        (uint256 reflection, uint256 balance) = _getRate();
        bool takeFee = !(excludedFromFee[from] || excludedFromFee[to]);
        (uint256 tax, uint256 liq, uint256 brn, uint256 mrk, uint256 ref) = _getFeeValues(amount, takeFee);

        _updateBalances(from, to, amount, reflection, balance, tax + liq + brn + mrk + ref);
        uint256 liqAmount = _reflectFee(from, reflection, balance, tax, liq, brn, mrk, ref);
        _takeLiquidity(liqAmount, reflection, balance);
    }

    function _updateBalances(
        address from,
        address to,
        uint256 amount,
        uint256 reflect,
        uint256 reflectBalance,
        uint256 fees
    ) private {
        uint256 rAmount = (amount * reflect) / reflectBalance;
        uint256 transferAmount = amount - fees;
        uint256 rTransferAmount = (transferAmount * reflect) / reflectBalance;

        if (excludedFromReward[from]) {
            uint256 balanceFrom = _balances[from];
            require(balanceFrom >= amount, "ERC20: transfer amount exceeds balance");
            _balances[from] = balanceFrom - amount;
            _totalRatedBalance += amount;
            _totalRatedReflection += rAmount;
        } else {
            uint256 balanceFrom = _reflections[from];
            require(balanceFrom >= rAmount, "ERC20: transfer amount exceeds balance");
            _reflections[from] = balanceFrom - rAmount;
        }
        if (excludedFromReward[to]) {
            _balances[to] += transferAmount;
            _totalRatedBalance -= transferAmount;
            _totalRatedReflection -= rTransferAmount;
        } else {
            _reflections[to] += rTransferAmount;
        }

        emit Transfer(from, to, transferAmount);
    }

    function _swapAndLiquify(uint256 amount) internal lockTheSwap {
        uint256 half = amount / 2;
        amount -= half;

        IUniswapV2Router02 _swapRouter = swapRouter;
        bool result = _swapTokensForBNB(half, _swapRouter);
        if (!result) {
            return;
        }
        uint256 balance = address(this).balance;
        result = _addLiquidity(amount, balance, _swapRouter);
        if (!result) {
            return;
        }

        emit LiquidityAdded(amount, balance);
    }

    function _swapTokensForBNB(uint256 tokenAmount, IUniswapV2Router02 _swapRouter) private returns (bool) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = swapWETH;

        _approve(address(this), address(_swapRouter), tokenAmount);
        try
            _swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                address(this),
                block.timestamp
            )
        {
            return true;
        } catch (bytes memory) {
            return false;
        }
    }

    function _addLiquidity(
        uint256 tokenAmount,
        uint256 ethAmount,
        IUniswapV2Router02 _swapRouter
    ) private returns (bool) {
        _approve(address(this), address(_swapRouter), tokenAmount);
        try
            _swapRouter.addLiquidityETH{value: ethAmount}(
                address(this),
                tokenAmount,
                0,
                0,
                liquidityAddress,
                block.timestamp
            )
        {
            return true;
        } catch (bytes memory) {
            return false;
        }
    }

    receive() external payable {
        require(_liqInProgress, "Only for swaps");
    }

    function recoverLockedTokens(address receiver, address token) external onlyOwner returns (uint256 balance) {
        require(token != address(this), "Only 3rd party");
        if (token == address(0)) {
            balance = address(this).balance;
            (bool success, ) = receiver.call{value: balance}("");
            require(success, "transfer eth failed");
            return balance;
        }
        balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(receiver, balance);

        emit RecoveredLockedTokens(token, receiver, balance);
    }

    function recoverLockedBNB() external onlyOwner {
        require(address(this).balance > 0, "Only 3rd party");
        payable(owner()).transfer(address(this).balance);
    }
}
