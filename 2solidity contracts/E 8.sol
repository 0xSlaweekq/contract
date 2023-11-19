// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

interface IFactory {
  function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IRouter {
  function factory() external pure returns (address);

  function WETH() external pure returns (address);

  function addLiquidityETH(
    address token,
    uint256 amountTokenDesired,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline
  ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external;
}

contract Energy8 is Context, Ownable, IERC20 {
  using SafeMath for uint256;
  mapping(address => mapping(address => uint256)) private _allowances;
  mapping(address => uint256) private _balances;
  mapping(address => uint256) private _startPeriodBalances;
  mapping(address => uint256) private _spentDuringPeriod;
  mapping(address => uint256) private _periodStartTime;
  mapping(address => bool) private _whitelist;
  mapping(address => bool) private _feeWhitelist;
  mapping(address => bool) private _blacklist;
  mapping(address => string) private _blacklistReasons;
  mapping(address => bool) private _sellers;
  mapping(address => bool) public admins;

  string private _name = 'Energy8';
  string private _symbol = 'E8';

  uint8 private _decimals = 9;
  uint256 private _totalSupply = 100000000000000 * 10 ** _decimals; // 100 000 000 000 000
  uint256 public periodDuration = 1 days;
  uint256 public minTokensForLiquidityGeneration = _totalSupply / 1000000; // 0.001% of total supply

  /*
    10000 - 100%
    1000 - 10%
    100 - 1%
    10 - 0.1%
    1 - 0.01%
  */
  // fees
  uint16 public fee = 0; // transfer fee 0%
  uint16 public buyFee = 0; // buy fee 0%
  uint16 public sellFee = 0; // sell fee 0%
  uint16 public liquidityFee = 0; // transfer liquidity fee 0%
  uint16 public sellLiquidityFee = 600; // sell liquidity fee 6%
  uint16 public buyLiquidityFee = 500; // buy liquidity fee 5%
  uint16 public marketingFee = 200; // marketing fee 2%

  address public marketingWallet;
  address public feeWallet;

  uint16 public maxTransferPercent = 3000; // 30%
  uint16 public maxHodlPercent = 100; // 1%

  // AMM addresses
  IRouter public router;
  address public pair;
  address private mainTokenInPair;

  address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

  modifier onlyAdmin() {
    require(admins[_msgSender()], 'Who are you?');
    _;
  }

  bool private isLocked;

  modifier lock() {
    isLocked = true;
    _;
    isLocked = false;
  }

  constructor(IRouter _router) {
    _balances[_msgSender()] = _totalSupply;

    mainTokenInPair = _router.WETH();

    pair = IFactory(_router.factory()).createPair(address(this), mainTokenInPair);

    // add owner and this contract to the whitelist for disable transfer limitations and fees
    _whitelist[_msgSender()] = true;
    _whitelist[address(this)] = true;
    _feeWhitelist[_msgSender()] = true;
    _feeWhitelist[address(this)] = true;

    _sellers[pair] = true;
    _sellers[address(_router)] = true;

    router = _router;

    marketingWallet = _msgSender();
    feeWallet = DEAD;

    admins[_msgSender()] = true;

    emit Transfer(address(0), _msgSender(), _totalSupply);
  }

  function getOwner() external view returns (address) {
    return owner();
  }

  function decimals() external view override returns (uint8) {
    return _decimals;
  }

  function symbol() external view override returns (string memory) {
    return _symbol;
  }

  function name() external view override returns (string memory) {
    return _name;
  }

  function totalSupply() external view override returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) external view override returns (uint256) {
    return _balances[account];
  }

  function transfer(address recipient, uint256 amount) external override returns (bool) {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount) external override returns (bool) {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, 'BEP20: transfer amount exceeds allowance'));
    return true;
  }

  function _approve(address owner, address spender, uint256 amount) internal {
    require(owner != address(0), 'ERC20: approve from the zero address');
    require(spender != address(0), 'ERC20: approve to the zero address');

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  receive() external payable {}

  function _transfer(address sender, address recipient, uint256 amount) internal {
    require(sender != address(0), 'ERC20: transfer from the zero address');
    require(recipient != address(0), 'ERC20: transfer to the zero address');
    require(sender != recipient, 'ERC20: The sender cannot be the recipient');
    require(amount != 0, 'ERC20: Transfer amount must be greater than zero');
    require(_balances[sender] >= amount, 'ERC20: transfer amount exceeds balance');

    uint256 amountWithFee = amount;

    uint256 liquidityFeeInTokens;
    uint256 marketingFeeInTokens;
    uint256 feeInTokens;

    // buy tokens
    if (_sellers[sender]) {
      if (!_feeWhitelist[recipient]) {
        liquidityFeeInTokens = _getPercentage(amount, buyLiquidityFee);
        marketingFeeInTokens = _getPercentage(amount, marketingFee);
        feeInTokens = _getPercentage(amount, buyFee);
        amountWithFee = amountWithFee.sub(marketingFeeInTokens).sub(feeInTokens).sub(liquidityFeeInTokens);
      }

      if (!_whitelist[recipient])
        _checkHodlPercent(recipient, amountWithFee, 'You cannot hold this amount of tokens. Looks like you are already a whale!');

      // sell tokens
    } else if (_sellers[recipient]) {
      require(!_blacklist[sender], _blacklistReasons[sender]);

      if (!_feeWhitelist[sender]) {
        liquidityFeeInTokens = _getPercentage(amount, sellLiquidityFee);
        marketingFeeInTokens = _getPercentage(amount, marketingFee);
        feeInTokens = _getPercentage(amount, sellFee);
        amountWithFee = amountWithFee.sub(marketingFeeInTokens).sub(feeInTokens).sub(liquidityFeeInTokens);
      }

      if (!_whitelist[sender])
        _checkAndUpdatePeriod(sender, amount, 'You can not sell this amount of tokens for the current period. Just relax and wait');

      // transfer tokens between addresses
    } else {
      require(!_blacklist[sender] && !_blacklist[_msgSender()], _blacklistReasons[sender]);

      if (!_feeWhitelist[sender] && !_feeWhitelist[_msgSender()]) {
        liquidityFeeInTokens = _getPercentage(amount, liquidityFee);
        marketingFeeInTokens = _getPercentage(amount, marketingFee);
        feeInTokens = _getPercentage(amount, fee);
        amountWithFee = amountWithFee.sub(marketingFeeInTokens).sub(feeInTokens).sub(liquidityFeeInTokens);
      }

      if (!_whitelist[recipient] && !_whitelist[_msgSender()])
        _checkHodlPercent(recipient, amountWithFee, 'Recipient cannot hold this amount of tokens. Looks like he is already a whale!');

      if (!_whitelist[sender] && !_whitelist[_msgSender()])
        _checkAndUpdatePeriod(sender, amount, 'You can not transfer this amount of tokens for the current period. Just relax and wait');
    }

    if (marketingFeeInTokens > 0) {
      _balances[marketingWallet] = _balances[marketingWallet].add(marketingFeeInTokens);
      emit Transfer(sender, marketingWallet, marketingFeeInTokens);
    }

    if (feeInTokens > 0) {
      _balances[feeWallet] = _balances[feeWallet].add(feeInTokens);
      emit Transfer(sender, feeWallet, feeInTokens);
    }

    if (liquidityFeeInTokens > 0) {
      uint256 contractTokenBalance = _balances[address(this)].add(liquidityFeeInTokens);

      _balances[address(this)] = contractTokenBalance;
      emit Transfer(sender, address(this), liquidityFeeInTokens);

      if (!isLocked && sender != pair && contractTokenBalance >= minTokensForLiquidityGeneration) {
        generateLiquidity(contractTokenBalance);
      }
    }

    _balances[sender] = _balances[sender].sub(amount);
    _balances[recipient] = _balances[recipient].add(amountWithFee);

    emit Transfer(sender, recipient, amountWithFee);
  }

  function generateLiquidity() external {
    generateLiquidity(_balances[address(this)]);
  }

  function generateLiquidity(uint256 amount) internal lock {
    uint256 tokensForSell = amount.div(2);
    uint256 tokensForLiquidity = amount.sub(tokensForSell);

    uint256 initialBalance = address(this).balance;

    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = mainTokenInPair;

    _approve(address(this), address(router), amount);

    router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokensForSell,
      0, // accept any amount
      path,
      address(this),
      block.timestamp
    );

    uint256 balance = address(this).balance.sub(initialBalance);

    router.addLiquidityETH{ value: balance }(
      address(this),
      tokensForLiquidity,
      0, // slippage is unavoidable
      0, // slippage is unavoidable
      DEAD,
      block.timestamp
    );
  }

  function _checkAndUpdatePeriod(address account, uint256 amount, string memory errorMessage) internal {
    bool _isPeriodEnd = block.timestamp > (_periodStartTime[account] + periodDuration);

    if (_isPeriodEnd) {
      _periodStartTime[account] = block.timestamp;
      _startPeriodBalances[account] = _balances[account];
      _spentDuringPeriod[account] = 0;
    }

    uint256 newSpentDuringPeriod = _spentDuringPeriod[account] + amount;
    uint256 accountCanSpent = _getPercentage(_startPeriodBalances[account], maxTransferPercent);

    require(newSpentDuringPeriod <= accountCanSpent, errorMessage);

    _spentDuringPeriod[account] = newSpentDuringPeriod;
  }

  function _checkHodlPercent(address account, uint256 amount, string memory erorrMessage) internal view {
    uint256 oneAccountCanHodl = _getPercentage(_totalSupply, maxHodlPercent);

    require((_balances[account] + amount) <= oneAccountCanHodl, erorrMessage);
  }

  function setSeller(address account, bool value) external onlyAdmin {
    _sellers[account] = value;
  }

  function setWhitelist(address account, bool value) external onlyAdmin {
    _whitelist[account] = value;
  }

  function setFeeWhitelist(address account, bool value) external onlyAdmin {
    _feeWhitelist[account] = value;
  }

  function setBlacklist(address account, bool value, string memory reason) external onlyAdmin {
    _blacklist[account] = value;
    _blacklistReasons[account] = reason;
  }

  function setAdmin(address account, bool value) external onlyOwner {
    admins[account] = value;
  }

  function setMaxHodlPercent(uint16 percent) external onlyAdmin {
    require(percent > 0 && percent <= 10000); // >0% - 100%
    maxHodlPercent = percent;
  }

  function setMaxTransferPercent(uint16 percent) external onlyAdmin {
    require(percent >= 100 && percent <= 10000); // 1% - 100%
    maxTransferPercent = percent;
  }

  function setPeriodDuration(uint256 time) external onlyAdmin {
    require(time <= 14 days);
    periodDuration = time;
  }

  function setRouter(IRouter _router) external onlyOwner {
    router = _router;
  }

  function setPair(address _pair) external onlyOwner {
    pair = _pair;
  }

  function setMainTokenInPair(address token) external onlyOwner {
    mainTokenInPair = token;
  }

  function setMinTokensForLiquidityGeneration(uint256 amount) external onlyOwner {
    minTokensForLiquidityGeneration = amount;
  }

  function setTaxFees(uint16 _fee, uint16 _buyFee, uint16 _sellFee) external onlyOwner {
    require(
      _fee <= 1000 && // 0% - 10%
        _buyFee <= 1000 && // 0% - 10%
        _sellFee <= 1000 // 0% - 10%
    );
    fee = _fee;
    buyFee = _buyFee;
    sellFee = _sellFee;
  }

  function setLiquidityFees(uint16 _liquidityFee, uint16 _buyLiquidityFee, uint16 _sellLiquidityFee) public onlyOwner {
    require(
      _liquidityFee <= 1000 && // 0% - 10%
        _buyLiquidityFee <= 1000 && // 0% - 10%
        _sellLiquidityFee <= 1000 // 0% - 10%
    );
    liquidityFee = _liquidityFee;
    buyLiquidityFee = _buyLiquidityFee;
    sellLiquidityFee = _sellLiquidityFee;
  }

  function setMarketingFee(uint16 _marketingFee) external onlyOwner {
    require(_marketingFee <= 250); // 0% - 2.5%
    marketingFee = _marketingFee;
  }

  function setMarketingWallet(address _marketingWallet) external onlyOwner {
    require(_marketingWallet != feeWallet);
    marketingWallet = _marketingWallet;
  }

  function setFeeWallet(address _feeWallet) external onlyOwner {
    require(_feeWallet != owner() && _feeWallet != marketingWallet);
    feeWallet = _feeWallet;
  }

  function disableLiquidityGeneration() external onlyOwner {
    setLiquidityFees(0, 0, 0);
  }

  function isSeller(address account) external view returns (bool) {
    return _sellers[account];
  }

  function isWhitelisted(address account) external view returns (bool) {
    return _whitelist[account];
  }

  function isExcludedFromFee(address account) external view returns (bool) {
    return _feeWhitelist[account];
  }

  function isBlacklisted(address account) external view returns (bool) {
    return _blacklist[account];
  }

  function blacklistReason(address account) external view returns (string memory) {
    return _blacklistReasons[account];
  }

  function getAccountPeriodInfo(address account) external view returns (uint256 startBalance, uint256 startTime, uint256 spent) {
    startBalance = _startPeriodBalances[account];
    startTime = _periodStartTime[account];
    spent = _spentDuringPeriod[account];
  }

  function _getPercentage(uint256 number, uint16 percent) internal pure returns (uint256) {
    return (number * percent) / 10000;
  }
}
