// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IStrategy {
    function identifier() external pure returns(bytes32);
    function invest(bytes calldata params) external payable;
    function recall(address recipient) external;
}