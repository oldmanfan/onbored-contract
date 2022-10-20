// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IConvexBaseReward {
    function rewards(address staker) external view returns(uint256);
    function balanceOf(address staker) external view returns(uint256);
}