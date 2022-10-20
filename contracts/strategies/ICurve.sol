// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ICurve {
    function add_liquidity(uint256[2] calldata amounts, uint256 deadline) external payable returns(uint256);
}