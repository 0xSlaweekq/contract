// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

interface ISafeSwapTradeRouter {
    struct Trade {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address payable to;
        uint256 deadline;
    }

    function setRouter(address _router) external;

    function setFeePercent(uint256 _feePercent) external;

    function sePercent(uint256 _percent) external;

    function addFfsWhitelist(address _wl) external;

    function removeFfsWhitelist(address _wl) external;

    function setFeeJar(address _feeJar) external;

    function swapExactTokensForETHAndFeeAmount(Trade calldata trade) external payable;

    function swapTokensForExactETHAndFeeAmount(Trade calldata trade) external payable;

    function swapExactETHForTokensWithFeeAmount(Trade calldata trade, uint256 _feeAmount) external payable;

    function swapETHForExactTokensWithFeeAmount(Trade calldata trade, uint256 _feeAmount) external payable;

    function swapExactTokensForTokensWithFeeAmount(Trade calldata trade) external payable;

    function swapTokensForExactTokensWithFeeAmount(Trade calldata trade) external payable;

    function getSwapFee(
        uint256 amountIn,
        uint256 _amountOut,
        address tokenA,
        address tokenB
    ) external view returns (uint256 _fee);

    function getFees(
        address[] memory _path,
        uint256 _amountIn,
        address _address
    )
        external
        view
        returns (
            uint256 totalBNBFee,
            uint256 dexFee,
            uint256 tokenAFee,
            uint256 tokenBFee
        );

    function getSwapFees(uint256 amountIn, address[] memory path) external view returns (uint256 _fees);
}
