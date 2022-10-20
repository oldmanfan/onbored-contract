// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IConvex {
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    function withdrawAll(uint256 _pid) external returns(bool);
    function depositAll(uint256 _pid, bool _stake) external returns(bool);
    function poolInfo(uint256 pid) external view returns(PoolInfo memory);
}