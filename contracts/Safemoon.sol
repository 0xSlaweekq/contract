/**
 *Submitted for verification at Etherscan.io on 2023-11-21
*/

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import '../libs/safemoon/SafeMathUpgradeable.sol';
import '../abstract/safemoon/OwnableUpgradeable.sol';
import '../interfaces/safemoon/ISafemoon.sol';
import '../interfaces/safemoon/IUniswapV2Factory.sol';
import '../interfaces/safemoon/IUniswapV2Router02.sol';
import '../interfaces/safemoon/ISafeSwapTradeRouter.sol';

contract Safemoon is ISafemoon, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    struct FeeTier {
        uint256 ecoSystemFee;
        uint256 liquidityFee;
        uint256 taxFee;
        uint256 ownerFee;
        uint256 burnFee;
        address ecoSystem;
        address owner;
    }

    struct FeeValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rFee;
        uint256 tTransferAmount;
        uint256 tEchoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tOwner;
        uint256 tBurn;
    }

    struct tFeeValues {
        uint256 tTransferAmount;
        uint256 tEchoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tOwner;
        uint256 tBurn;
    }

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) private _isBlacklisted;
    mapping(address => uint256) private _accountsTier;

    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;
    uint256 private _maxFee;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    FeeTier public _defaultFees;
    FeeTier private _previousFees;
    FeeTier private _emptyFees;

    FeeTier[] private feeTiers;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public WBNB;
    address private migration;
    address private _initializerAccount;
    address public _burnAddress;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled;

    uint256 public _maxTxAmount;
    uint256 private numTokensSellToAddToLiquidity;

    bool private _upgraded;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    modifier lockUpgrade() {
        require(!_upgraded, "Safemoon: Already upgraded");
        _;
        _upgraded = true;
    }

    modifier checkTierIndex(uint256 _index) {
        require(feeTiers.length > _index, "Safemoon: Invalid tier index");
        _;
    }

    modifier preventBlacklisted(address _account, string memory errorMsg) {
        require(!_isBlacklisted[_account], errorMsg);
        _;
    }

    modifier isRouter(address _sender) {
        {
            uint32 size;
            assembly {
                size := extcodesize(_sender)
            }
            if (size > 0) {
                uint256 senderTier = _accountsTier[_sender];
                if (senderTier == 0) {
                    IUniswapV2Router02 _routerCheck = IUniswapV2Router02(_sender);
                    try _routerCheck.factory() returns (address factory) {
                        _accountsTier[_sender] = 1;
                    } catch {}
                }
            }
        }

        _;
    }

    uint256 public numTokensToCollectBNB;
    uint256 public numOfBnbToSwapAndEvolve;

    bool inSwapAndEvolve;
    bool public swapAndEvolveEnabled;

    /**
     * @dev
     * We create 2 variables _rTotalExcluded and _tTotalExcluded that store total t and r excluded
     * So for any actions such as add, remove exclude wallet or increase, decrease exclude amount, we will update
     * _rTotalExcluded and _tTotalExcluded
     * and in _getCurrentSupply() function, we remove for loop by using _rTotalExcluded and _tTotalExcluded
     * But this contract using proxy pattern, so when we upgrade contract,
     *  we need to call updateTotalExcluded() to init value of _rTotalExcluded and _tTotalExcluded
     */
    uint256 private _rTotalExcluded;
    uint256 private _tTotalExcluded;

    mapping(address => bool) public listIgnoreCollectBNBAddresses; // list pairs addresses that not call collectBNB function
    address public bridgeBurnAddress;
    mapping(address => bool) public whitelistMint;
    bool public isPaused;
    mapping(address => bool) public whitelistPause;
    mapping(address => bool) public isSFMPair;

    event SwapAndEvolveEnabledUpdated(bool enabled);
    event SwapAndEvolve(uint256 bnbSwapped, uint256 tokenReceived, uint256 bnbIntoLiquidity);
    event AddIgnoreCollectBNBAddress(address ignoreAddress);
    event RemoveIgnoreCollectBNBAddress(address ignoreAddress);
    event WhitelistPause(address user, bool value);
    event SetSFMPair(address pair, bool value);
    event PauseContract(bool value);

    modifier onlyWhitelistMint() {
        require(whitelistMint[msg.sender], "Invalid");
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused || whitelistPause[msg.sender], "Paused");
        _;
    }

    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Safemoon_v2_init_unchained();
    }

    function __Safemoon_v2_init_unchained() internal initializer {
        _name = "SafeMoon";
        _symbol = "SFM";
        _decimals = 9;

        _tTotal = 1000000 * 10**6 * 10**9;
        _rTotal = (MAX - (MAX % _tTotal));
        _maxFee = 1000;

        // swapAndLiquifyEnabled = true;

        _maxTxAmount = 5000 * 10**6 * 10**9;
        numTokensSellToAddToLiquidity = 500 * 10**6 * 10**9;

        _burnAddress = 0x000000000000000000000000000000000000dEaD;
        _initializerAccount = _msgSender();
        _rOwned[_initializerAccount] = _rTotal;
        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        //
        __Safemoon_tiers_init();

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function initRouterAndPair(address _router) external onlyOwner {
        uniswapV2Router = IUniswapV2Router02(_router);
        WBNB = uniswapV2Router.WETH();
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), WBNB, address(this));
    }

    function __Safemoon_tiers_init() internal initializer {
        _defaultFees = _addTier(0, 500, 500, 0, 0, address(0), address(0));
        _addTier(50, 50, 100, 0, 0, address(0), address(0));
        _addTier(50, 50, 100, 100, 0, address(0), address(0));
        _addTier(100, 125, 125, 150, 0, address(0), address(0));
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override whenNotPaused returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance")
        );
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflectionFromTokenInTiers(
        uint256 tAmount,
        uint256 _tierIndex,
        bool deductTransferFee
    ) public view returns (uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            FeeValues memory _values = _getValues(tAmount, _tierIndex);
            return _values.rAmount;
        } else {
            FeeValues memory _values = _getValues(tAmount, _tierIndex);
            return _values.rTransferAmount;
        }
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns (uint256) {
        return reflectionFromTokenInTiers(tAmount, 0, deductTransferFee);
    }

    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "Invalid");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
            _tTotalExcluded = _tTotalExcluded.add(_tOwned[account]);
            _rTotalExcluded = _rTotalExcluded.add(_rOwned[account]);
        }

        _isExcluded[account] = true;
        _excluded.push(account);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Invalid");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _rOwned[account] = _tOwned[account] * _getRate();
                _tTotalExcluded = _tTotalExcluded.sub(_tOwned[account]);
                _rTotalExcluded = _rTotalExcluded.sub(_rOwned[account]);
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function whitelistAddress(address _account, uint256 _tierIndex)
        public
        onlyOwner
        checkTierIndex(_tierIndex)
        preventBlacklisted(_account, "Safemoon: Selected account is in blacklist")
    {
        require(_account != address(0), "Safemoon: Invalid address");
        _accountsTier[_account] = _tierIndex;
    }

    function excludeWhitelistedAddress(address _account) public onlyOwner {
        require(_account != address(0), "Safemoon: Invalid address");
        require(_accountsTier[_account] > 0, "Safemoon: Account is not in whitelist");
        _accountsTier[_account] = 0;
    }

    function accountTier(address _account) public view returns (FeeTier memory) {
        return feeTiers[_accountsTier[_account]];
    }

    function isWhitelisted(address _account) public view returns (bool) {
        return _accountsTier[_account] > 0;
    }

    function checkFees(FeeTier memory _tier) internal view returns (FeeTier memory) {
        uint256 _fees = _tier.ecoSystemFee.add(_tier.liquidityFee).add(_tier.taxFee).add(_tier.ownerFee).add(
            _tier.burnFee
        );
        require(_fees <= _maxFee, "Safemoon: Fees exceeded max limitation");

        return _tier;
    }

    function checkFeesChanged(
        FeeTier memory _tier,
        uint256 _oldFee,
        uint256 _newFee
    ) internal view {
        uint256 _fees = _tier
            .ecoSystemFee
            .add(_tier.liquidityFee)
            .add(_tier.taxFee)
            .add(_tier.ownerFee)
            .add(_tier.burnFee)
            .sub(_oldFee)
            .add(_newFee);

        require(_fees <= _maxFee, "Safemoon: Fees exceeded max limitation");
    }

    function setEcoSystemFeePercent(uint256 _tierIndex, uint256 _ecoSystemFee)
        external
        onlyOwner
        checkTierIndex(_tierIndex)
    {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.ecoSystemFee, _ecoSystemFee);
        feeTiers[_tierIndex].ecoSystemFee = _ecoSystemFee;
        if (_tierIndex == 0) {
            _defaultFees.ecoSystemFee = _ecoSystemFee;
        }
    }

    function setLiquidityFeePercent(uint256 _tierIndex, uint256 _liquidityFee)
        external
        onlyOwner
        checkTierIndex(_tierIndex)
    {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.liquidityFee, _liquidityFee);
        feeTiers[_tierIndex].liquidityFee = _liquidityFee;
        if (_tierIndex == 0) {
            _defaultFees.liquidityFee = _liquidityFee;
        }
    }

    function setTaxFeePercent(uint256 _tierIndex, uint256 _taxFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.taxFee, _taxFee);
        feeTiers[_tierIndex].taxFee = _taxFee;
        if (_tierIndex == 0) {
            _defaultFees.taxFee = _taxFee;
        }
    }

    function setOwnerFeePercent(uint256 _tierIndex, uint256 _ownerFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.ownerFee, _ownerFee);
        feeTiers[_tierIndex].ownerFee = _ownerFee;
        if (_tierIndex == 0) {
            _defaultFees.ownerFee = _ownerFee;
        }
    }

    function setBurnFeePercent(uint256 _tierIndex, uint256 _burnFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.burnFee, _burnFee);
        feeTiers[_tierIndex].burnFee = _burnFee;
        if (_tierIndex == 0) {
            _defaultFees.burnFee = _burnFee;
        }
    }

    function setEcoSystemFeeAddress(uint256 _tierIndex, address _ecoSystem)
        external
        onlyOwner
        checkTierIndex(_tierIndex)
    {
        require(_ecoSystem != address(0), "Safemoon: Address Zero is not allowed");
        excludeFromReward(_ecoSystem);
        feeTiers[_tierIndex].ecoSystem = _ecoSystem;
        if (_tierIndex == 0) {
            _defaultFees.ecoSystem = _ecoSystem;
        }
    }

    function setOwnerFeeAddress(uint256 _tierIndex, address _owner) external onlyOwner checkTierIndex(_tierIndex) {
        require(_owner != address(0), "Safemoon: Address Zero is not allowed");
        excludeFromReward(_owner);
        feeTiers[_tierIndex].owner = _owner;
        if (_tierIndex == 0) {
            _defaultFees.owner = _owner;
        }
    }

    function addTier(
        uint256 _ecoSystemFee,
        uint256 _liquidityFee,
        uint256 _taxFee,
        uint256 _ownerFee,
        uint256 _burnFee,
        address _ecoSystem,
        address _owner
    ) public onlyOwner {
        _addTier(_ecoSystemFee, _liquidityFee, _taxFee, _ownerFee, _burnFee, _ecoSystem, _owner);
    }

    function _addTier(
        uint256 _ecoSystemFee,
        uint256 _liquidityFee,
        uint256 _taxFee,
        uint256 _ownerFee,
        uint256 _burnFee,
        address _ecoSystem,
        address _owner
    ) internal returns (FeeTier memory) {
        FeeTier memory _newTier = checkFees(
            FeeTier(_ecoSystemFee, _liquidityFee, _taxFee, _ownerFee, _burnFee, _ecoSystem, _owner)
        );
        excludeFromReward(_ecoSystem);
        excludeFromReward(_owner);
        feeTiers.push(_newTier);

        return _newTier;
    }

    function feeTier(uint256 _tierIndex) public view checkTierIndex(_tierIndex) returns (FeeTier memory) {
        return feeTiers[_tierIndex];
    }

    function blacklistAddress(address account) public onlyOwner {
        _isBlacklisted[account] = true;
        _accountsTier[account] = 0;
    }

    function unBlacklistAddress(address account) public onlyOwner {
        _isBlacklisted[account] = false;
    }

    function updateRouterAndPair(address _uniswapV2Router, address _uniswapV2Pair) public onlyOwner {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV2Pair = _uniswapV2Pair;
        WBNB = uniswapV2Router.WETH();
    }

    function setDefaultSettings() external onlyOwner {
        swapAndLiquifyEnabled = false;
        swapAndEvolveEnabled = true;
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**4);
    }

    function setSwapAndEvolveEnabled(bool _enabled) public onlyOwner {
        swapAndEvolveEnabled = _enabled;
        emit SwapAndEvolveEnabledUpdated(_enabled);
    }

    //to receive BNB from uniswapV2Router when swapping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount, uint256 _tierIndex) private view returns (FeeValues memory) {
        tFeeValues memory tValues = _getTValues(tAmount, _tierIndex);
        uint256 tTransferFee = tValues.tLiquidity.add(tValues.tEchoSystem).add(tValues.tOwner).add(tValues.tBurn);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tValues.tFee,
            tTransferFee,
            _getRate()
        );
        return
            FeeValues(
                rAmount,
                rTransferAmount,
                rFee,
                tValues.tTransferAmount,
                tValues.tEchoSystem,
                tValues.tLiquidity,
                tValues.tFee,
                tValues.tOwner,
                tValues.tBurn
            );
    }

    function _getTValues(uint256 tAmount, uint256 _tierIndex) private view returns (tFeeValues memory) {
        FeeTier memory tier = feeTiers[_tierIndex];
        tFeeValues memory tValues = tFeeValues(
            0,
            calculateFee(tAmount, tier.ecoSystemFee),
            calculateFee(tAmount, tier.liquidityFee),
            calculateFee(tAmount, tier.taxFee),
            calculateFee(tAmount, tier.ownerFee),
            calculateFee(tAmount, tier.burnFee)
        );

        tValues.tTransferAmount = tAmount
            .sub(tValues.tEchoSystem)
            .sub(tValues.tFee)
            .sub(tValues.tLiquidity)
            .sub(tValues.tOwner)
            .sub(tValues.tBurn);

        return tValues;
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tTransferFee,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTransferFee = tTransferFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rTransferFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        if (_rTotalExcluded > _rTotal || _tTotalExcluded > _tTotal) {
            return (_rTotal, _tTotal);
        }
        uint256 rSupply = _rTotal.sub(_rTotalExcluded);
        uint256 tSupply = _tTotal.sub(_tTotalExcluded);

        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);

        return (rSupply, tSupply);
    }

    function calculateFee(uint256 _amount, uint256 _fee) private pure returns (uint256) {
        if (_fee == 0) return 0;
        return _amount.mul(_fee).div(10**4);
    }

    function removeAllFee() private {
        _previousFees = feeTiers[0];
        feeTiers[0] = _emptyFees;
    }

    function restoreAllFee() private {
        feeTiers[0] = _previousFees;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _isBlacklisted[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    )
        private
        preventBlacklisted(owner, "Safemoon: Owner address is blacklisted")
        preventBlacklisted(spender, "Safemoon: Spender address is blacklisted")
    {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    )
        private
        preventBlacklisted(_msgSender(), "Safemoon: Address is blacklisted")
        preventBlacklisted(from, "Safemoon: From address is blacklisted")
        preventBlacklisted(to, "Safemoon: To address is blacklisted")
        isRouter(_msgSender())
    {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(_canAction(from, to), "Paused");

        if (from != owner() && to != owner())
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >= numTokensToCollectBNB;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            swapAndEvolveEnabled &&
            !_isInCollectBNBWhitelist(from) &&
            !_isInCollectBNBWhitelist(to)
        ) {
            contractTokenBalance = numTokensToCollectBNB;
            collectBNB(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        uint256 tierIndex = 0;

        if (takeFee) {
            tierIndex = _accountsTier[from];

            if (_msgSender() != from) {
                tierIndex = _accountsTier[_msgSender()];
            }
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, tierIndex, takeFee);
    }

    function _canAction(address from, address to) private view returns (bool) {
        if (!isPaused) {
            return true;
        }
        if (whitelistPause[from] && whitelistPause[to]) {
            return true;
        }
        if (whitelistPause[from] && !isSFMPair[from]) {
            return true;
        }
        return false;
    }

    function collectBNB(uint256 contractTokenBalance) private lockTheSwap {
        swapTokensForBnb(contractTokenBalance);
    }

    function swapTokensForBnb(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        ISafeSwapTradeRouter tradeRouter = ISafeSwapTradeRouter(uniswapV2Router.routerTrade());
        //        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // get feeAmount
        uint256 feeAmount = tradeRouter.getSwapFees(tokenAmount, path);

        //        (, uint256 feeAmount, uint256 tokenAFee, ) = tradeRouter.getFees(path, tokenAmount, address(this));
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        _approve(address(this), address(tradeRouter), tokenAmount);
        ISafeSwapTradeRouter.Trade memory trade = ISafeSwapTradeRouter.Trade({
            amountIn: tokenAmount,
            amountOut: 0,
            path: path,
            to: payable(address(this)),
            deadline: block.timestamp
        });
        tradeRouter.swapExactTokensForETHAndFeeAmount{ value: feeAmount }(trade);
    }

    function swapAndEvolve() public onlyOwner lockTheSwap {
        // split the contract balance into halves
        uint256 contractBnbBalance = address(this).balance;
        require(contractBnbBalance >= numOfBnbToSwapAndEvolve, "BNB balance is not reach for S&E Threshold");

        contractBnbBalance = numOfBnbToSwapAndEvolve;

        uint256 half = contractBnbBalance.div(2);
        uint256 otherHalf = contractBnbBalance.sub(half);

        // capture the contract's current BNB balance.
        // this is so that we can capture exactly the amount of BNB that the
        // swap creates, and not make the liquidity event include any BNB that
        // has been manually sent to the contract
        uint256 initialBalance = ISafemoon(address(this)).balanceOf(msg.sender);
        // swap BNB for Tokens
        swapBnbForTokens(half);

        // how much BNB did we just swap into?
        uint256 newBalance = ISafemoon(address(this)).balanceOf(msg.sender);
        uint256 swapeedToken = newBalance.sub(initialBalance);

        _approve(msg.sender, address(this), swapeedToken);
        ISafemoon(address(this)).transferFrom(msg.sender, address(this), swapeedToken);
        // add liquidity to uniswap
        addLiquidity(swapeedToken, otherHalf);
        emit SwapAndEvolve(half, swapeedToken, otherHalf);
    }

    function swapBnbForTokens(uint256 bnbAmount) private {
        // generate the uniswap pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        ISafeSwapTradeRouter tradeRouter = ISafeSwapTradeRouter(uniswapV2Router.routerTrade());
        _approve(owner(), address(uniswapV2Router), bnbAmount);

        // get feeAmount
        uint256 feeAmount = tradeRouter.getSwapFees(bnbAmount, path);
        ISafeSwapTradeRouter.Trade memory trade = ISafeSwapTradeRouter.Trade({
            amountIn: bnbAmount,
            amountOut: 0,
            path: path,
            to: payable(owner()),
            deadline: block.timestamp
        });
        tradeRouter.swapExactETHForTokensWithFeeAmount{ value: bnbAmount + feeAmount }(trade, feeAmount);
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{ value: bnbAmount }(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        uint256 tierIndex,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount, tierIndex);
        } else if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount, tierIndex);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount, tierIndex);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount, tierIndex);
        }

        if (!takeFee) restoreAllFee();
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        //        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(_values.tTransferAmount);
        //        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);

        if (_values.tTransferAmount > tAmount) {
            uint256 tmpValue = _values.tTransferAmount - tAmount;
            _tTotalExcluded = _tTotalExcluded.add(tmpValue);
        } else {
            uint256 tmpValue = tAmount - _values.tTransferAmount;
            _tTotalExcluded = _tTotalExcluded.sub(tmpValue);
        }
        if (_values.rTransferAmount > _values.rAmount) {
            uint256 tmpValue = _values.rTransferAmount - _values.rAmount;
            _rTotalExcluded = _rTotalExcluded.add(tmpValue);
        } else {
            uint256 tmpValue = _values.rAmount - _values.rTransferAmount;
            _rTotalExcluded = _rTotalExcluded.sub(tmpValue);
        }
        //        _tTotalExcluded = _tTotalExcluded.add(_values.tTransferAmount).sub(tAmount);
        //        _rTotalExcluded = _rTotalExcluded.add(_values.rTransferAmount).sub(_values.rAmount);

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(_values.tTransferAmount);
        //        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _tTotalExcluded = _tTotalExcluded.add(_values.tTransferAmount);
        _rTotalExcluded = _rTotalExcluded.add(_values.rTransferAmount);

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        //        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _tTotalExcluded = _tTotalExcluded.sub(tAmount);
        _rTotalExcluded = _rTotalExcluded.sub(_values.rAmount);

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _takeFees(
        address sender,
        FeeValues memory values,
        uint256 tierIndex
    ) private {
        _takeFee(sender, values.tLiquidity, address(this));
        _takeFee(sender, values.tEchoSystem, feeTiers[tierIndex].ecoSystem);
        _takeFee(sender, values.tOwner, feeTiers[tierIndex].owner);
        _takeBurn(sender, values.tBurn);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _takeFee(
        address sender,
        uint256 tAmount,
        address recipient
    ) private {
        if (recipient == address(0)) return;
        if (tAmount == 0) return;

        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount.mul(currentRate);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);

        if (_isExcluded[recipient]) {
            _tOwned[recipient] = _tOwned[recipient].add(tAmount);
            _tTotalExcluded = _tTotalExcluded.add(tAmount);
            _rTotalExcluded = _rTotalExcluded.add(rAmount);
        }

        emit Transfer(sender, recipient, tAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _takeBurn(address sender, uint256 _amount) private {
        if (_amount == 0) return;
        _tOwned[_burnAddress] = _tOwned[_burnAddress].add(_amount);
        uint256 _rAmount = _amount * _getRate();
        _rOwned[_burnAddress] = _rOwned[_burnAddress].add(_rAmount);
        if (_isExcluded[_burnAddress]) {
            _rTotalExcluded = _rTotalExcluded.add(_rAmount);
            _tTotalExcluded = _tTotalExcluded.add(_amount);
        }

        emit Transfer(sender, _burnAddress, _amount);
    }

    function setMigrationAddress(address _migration) public onlyOwner {
        migration = _migration;
    }

    function isMigrationStarted() external view override returns (bool) {
        return migration != address(0);
    }

    function migrate(address account, uint256 amount)
        external
        override
        preventBlacklisted(account, "Safemoon: Migrated account is blacklisted")
    {
        require(migration != address(0), "Safemoon: Migration is not started");
        require(_msgSender() == migration, "Safemoon: Not Allowed");
        _migrate(account, amount);
    }

    function _migrate(address account, uint256 amount) private {
        require(account != address(0), "BEP20: mint to the zero address");

        _tokenTransfer(owner(), account, amount, 0, false);
    }

    function feeTiersLength() public view returns (uint256) {
        return feeTiers.length;
    }

    function updateBurnAddress(address _newBurnAddress) external onlyOwner {
        _burnAddress = _newBurnAddress;
        excludeFromReward(_newBurnAddress);
    }

    function withdrawToken(address _token, uint256 _amount) public onlyOwner {
        ISafemoon(_token).transfer(msg.sender, _amount);
    }

    function setNumberOfTokenToCollectBNB(uint256 _numToken) public onlyOwner {
        numTokensToCollectBNB = _numToken;
    }

    function setNumOfBnbToSwapAndEvolve(uint256 _numBnb) public onlyOwner {
        numOfBnbToSwapAndEvolve = _numBnb;
    }

    function withdrawBnb(uint256 _amount) public onlyOwner {
        payable(msg.sender).transfer(_amount);
    }

    function addListIgnoreCollectBNBOnTransferAddresses(address[] calldata _addresses) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i = 0; i < len; i++) {
            address addr = _addresses[i];
            if (listIgnoreCollectBNBAddresses[addr]) continue;

            listIgnoreCollectBNBAddresses[addr] = true;
            emit AddIgnoreCollectBNBAddress(addr);
        }
    }

    function removeListIgnoreCollectBNBOnTransferAddresses(address[] calldata _addresses) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i = 0; i < len; i++) {
            address addr = _addresses[i];
            if (!listIgnoreCollectBNBAddresses[addr]) continue;

            listIgnoreCollectBNBAddresses[addr] = false;
            emit RemoveIgnoreCollectBNBAddress(addr);
        }
    }

    function _isInCollectBNBWhitelist(address _addr) private view returns (bool) {
        return listIgnoreCollectBNBAddresses[_addr];
    }

    function setBridgeBurnAddress(address _burn) public onlyOwner {
        bridgeBurnAddress = _burn;
    }

    function setWhitelistMintBurn(address _wl, bool value) public onlyOwner {
        whitelistMint[_wl] = value;
    }

    function mint(address user, uint256 amount) public whenNotPaused onlyWhitelistMint {
        if (msg.sender != owner()) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }
        _tokenTransfer(bridgeBurnAddress, user, amount, 0, false);
    }

    function burn(uint256 amount) public whenNotPaused onlyWhitelistMint {
        if (msg.sender != owner()) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }
        _tokenTransfer(msg.sender, bridgeBurnAddress, amount, 0, false);
    }

    function setWhitelistPause(address user, bool value) public onlyOwner {
        whitelistPause[user] = value;
        emit WhitelistPause(user, value);
    }

    function setPause(bool value) public onlyOwner {
        isPaused = value;
    }

    function setSFMPair(address pair, bool value) public onlyOwner {
        isSFMPair[pair] = value;
        emit SetSFMPair(pair, value);
    }
}
