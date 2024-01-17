// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function createPair(address tokenA, address tokenB, address to) external returns (address pair);
}
