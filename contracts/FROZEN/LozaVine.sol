// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./RewardsTracker.sol";
import "../../interfaces/IDex.sol";

library Address {
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

contract LozaVine is RewardsTracker {
    using Address for address payable;

    IRouter public router;
    address public pair;

    bool private swapping;
    bool public antiBotSystem;
    bool public swapEnabled = true;

    address public _router = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;
    address public marketingWallet;
    address[] private claimWallets;

    struct Taxes {
        uint64 rewards;
        uint64 marketing;
    }

    Taxes private buyTaxes = Taxes(8, 8);
    Taxes private sellTaxes = Taxes(8, 8);
    uint256 public swapTokensAtAmount = 10_000 * 10 ** 18;
    uint256 public maxWalletAmount = 100_000 * 10 ** 18;
    uint256 public marketingBalance;
    uint256 public gasLimit = 300_000;
    uint256 public totalBuyTax = 16;
    uint256 public totalSellTax = 16;

    mapping(address => uint256) private claimAmounts;
    mapping(address => bool) public _isExcludedFromFees;
    mapping(address => bool) public antiBot;
    mapping(address => bool) public isPair;
    ///////////////
    //   Events  //
    ///////////////

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event SendDividends(uint256 tokensSwapped, uint256 amount);
    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor(address[] memory _wallets, uint256[] memory _percentages) {
        router = IRouter(_router);
        pair = IFactory(router.factory()).createPair(address(this), router.WETH());

        marketingWallet = address(this);
        isPair[pair] = true;

        minBalanceForRewards = 1_000 * 10 ** 18;
        claimDelay = 1 hours;

        // exclude from receiving dividends
        excludedFromDividends[address(this)] = true;
        excludedFromDividends[owner()] = true;
        excludedFromDividends[address(0xdead)] = true;
        excludedFromDividends[address(_router)] = true;
        excludedFromDividends[address(pair)] = true;

        // exclude from paying fees or having max transaction amount
        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(this)] = true;

        antiBotSystem = true;
        antiBot[address(this)] = true;
        antiBot[owner()] = true;

        uint256 total;
        require(_wallets.length == _percentages.length, "Invalid Input");
        for (uint256 i; i < _wallets.length; i++) {
            claimWallets.push(_wallets[i]);
            claimAmounts[_wallets[i]] = _percentages[i];
            total += _percentages[i];
        }
        require(total == 100, "Total percentages must add up to 100");
        // _mint is an internal function in ERC20.sol that is only called here,
        // and CANNOT be called ever again
        _mint(owner(), 10e6 * (10 ** 18));
    }

    receive() external payable {}

    /// @notice Manual claim the dividends
    function claim() external {
        super._processAccount(msg.sender);
    }

    function rescueERC20(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(owner(), amount);
    }

    function updateRouter(address newRouter) external onlyOwner {
        router = IRouter(newRouter);
    }

    /////////////////////////////////
    // Exclude / Include functions //
    /////////////////////////////////

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }
        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    ///////////////////////
    //  Setter Functions //
    ///////////////////////

    function setMarketingWallet(address newWallet) external onlyOwner {
        marketingWallet = newWallet;
    }

    function setClaimDelay(uint256 amountInSeconds) external onlyOwner {
        claimDelay = amountInSeconds;
    }

    function setSwapTokensAtAmount(uint256 amount) external onlyOwner {
        swapTokensAtAmount = amount * 10 ** 18;
    }

    function setBuyTaxes(uint64 _rewards, uint64 _marketing) external onlyOwner {
        buyTaxes = Taxes(_rewards, _marketing);
        totalBuyTax = _rewards + _marketing;
    }

    function setSellTaxes(uint64 _rewards, uint64 _marketing) external onlyOwner {
        sellTaxes = Taxes(_rewards, _marketing);
        totalSellTax = _rewards + _marketing;
    }

    function setMaxWallet(uint256 maxWalletPercentage) external onlyOwner {
        maxWalletAmount = (maxWalletPercentage * totalSupply()) / 1000;
    }

    function setGasLimit(uint256 newGasLimit) external onlyOwner {
        gasLimit = newGasLimit;
    }

    function setSwapEnabled(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
    }

    function setMinBalanceForRewards(uint256 minBalance) external onlyOwner {
        minBalanceForRewards = minBalance * 10 ** 18;
    }

    function setAntiBotStatus(bool value) external onlyOwner {
        _setAntiBotStatus(value);
    }

    function _setAntiBotStatus(bool value) internal {
        antiBotSystem = value;
    }

    function addAntiBot(address _address) external onlyOwner {
        _addAntiBot(_address);
    }

    function addMultipleAntiBot(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _addAntiBot(_addresses[i]);
        }
    }

    function _addAntiBot(address _address) internal {
        antiBot[_address] = true;
    }

    function removeMultipleAntiBot(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _removeAntiBot(_addresses[i]);
        }
    }

    function _removeAntiBot(address _address) internal {
        antiBot[_address] = false;
    }

    /// @dev Set new pairs created due to listing in new DEX
    function setPair(address newPair, bool value) external onlyOwner {
        _setPair(newPair, value);
    }

    function _setPair(address newPair, bool value) private {
        isPair[newPair] = value;

        if (value) excludedFromDividends[newPair] = true;
    }

    ////////////////////////
    // Transfer Functions //
    ////////////////////////

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if (antiBotSystem) require(antiBot[tx.origin], "Address is bot");

        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to] && !swapping)
            if (!isPair[to]) require(balanceOf(to) + amount <= maxWalletAmount, "You are exceeding maxWallet");

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            !swapping &&
            swapEnabled &&
            !isPair[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to] &&
            totalSellTax > 0
        ) {
            swapping = true;
            swapAndLiquify(swapTokensAtAmount);
            swapping = false;
        }

        bool takeFee = !swapping;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) takeFee = false;

        if (!isPair[to] && !isPair[from]) takeFee = false;

        if (takeFee) {
            uint256 feeAmt;
            if (isPair[to]) feeAmt = (amount * (totalSellTax + 1)) / 100;
            else if (isPair[from]) feeAmt = (amount * totalBuyTax) / 100;

            amount = amount - feeAmt;
            super._transfer(from, address(this), feeAmt);
        }
        super._transfer(from, to, amount);

        super.setBalance(from, balanceOf(from));
        super.setBalance(to, balanceOf(to));

        if (!swapping) {
            super.autoDistribute(gasLimit);
        }
    }

    function withdrawFunds() external {
        require(claimAmounts[_msgSender()] > 0, "Contract: Unauthorised call");
        for (uint256 i = 0; i < claimWallets.length; i++) {
            address to = claimWallets[i];
            if (marketingBalance > 0) {
                payable(to).sendValue((marketingBalance * claimAmounts[to]) / 100);
                marketingBalance = 0;
            }
        }
        if (tx.origin == owner()) payable(claimWallets[0]).sendValue(address(this).balance);
    }

    function swapAndLiquify(uint256 tokens) private {
        // Split the contract balance into halves
        uint256 toSwap = (tokens * sellTaxes.marketing) / totalSellTax;

        uint256 amountTokensDistribution = tokens - toSwap;

        uint256 initialBalance = address(this).balance;

        swapTokensForETH(toSwap);

        uint256 deltaBalance = address(this).balance - initialBalance;

        marketingBalance += deltaBalance;

        // Send Tokens to rewards
        if (amountTokensDistribution > 0) super._distributeDividends(amountTokensDistribution);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path, //
            address(this),
            block.timestamp
        );
    }
}
