// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IStrategy.sol";
import "./strategies/LidoCurveConvexStrategy.sol";

contract OnBored is Ownable {
    // mapping of stratigies, Strategy Identifier => Strategy Implements;
    mapping(bytes32 => address) public stratigies;
    mapping(bytes32 => bytes32) proxyCodeHash;

    // mapping of invester, invester address => Strategy Id => Proxy Address
    mapping(address => mapping(bytes32 => address)) public investers;

    event StrategyRegistered(address indexed strategy);
    event Invested(address indexed sender, address indexed proxy, uint256 amount);
    event Recalled(address indexed sender, address indexed proxy);

    constructor() {

    }

    function registerStrategy(IStrategy strategy) public onlyOwner {
        bytes32 id = strategy.identifier();
        stratigies[id] = address(strategy);
        emit StrategyRegistered(address(strategy));
    }

    function proxyHolderAddress(address invester, bytes32 strategyId) internal view returns(address proxy) {

        bytes32 salt = keccak256(abi.encodePacked(invester, strategyId));
        proxy = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                address(this),
                salt,
                proxyCodeHash[strategyId]
            )))));
    }

    function invest(bytes32 strategyId, bytes memory params) public payable {
        require(stratigies[strategyId] != address(0), "strategy not registered");

        LidoCurveConvexStrategy strategy = LidoCurveConvexStrategy(payable(investers[msg.sender][strategyId]));
        if (address(strategy) == address(0)) {
            bytes memory miniProxy = bytes.concat(bytes20(0x3D602d80600A3D3981F3363d3d373d3D3D363d73), bytes20(stratigies[strategyId]), bytes15(0x5af43d82803e903d91602b57fd5bf3));
            proxyCodeHash[strategyId] = keccak256(abi.encodePacked(miniProxy));

            bytes32 salt = keccak256(abi.encodePacked(msg.sender, strategyId));
            assembly {
                strategy := create2(0, add(miniProxy, 32), mload(miniProxy), salt)
            }

            investers[msg.sender][strategyId] = address(strategy);
        }
        strategy.invest{value: msg.value}(params);

        emit Invested(msg.sender, address(strategy), msg.value);
    }

    function recall(bytes32 strategyId) public {
        require(investers[msg.sender][strategyId] != address(0), "not invest this strategy");

        LidoCurveConvexStrategy strategy = LidoCurveConvexStrategy(payable(investers[msg.sender][strategyId]));
        strategy.recall(msg.sender);

        emit Recalled(msg.sender, address(strategy));
    }
}