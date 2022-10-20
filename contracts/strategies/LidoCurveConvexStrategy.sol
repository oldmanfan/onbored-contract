// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../IStrategy.sol";
import "./ICurve.sol";
import "./IConvex.sol";
import "./IConvexRewards.sol";

import "hardhat/console.sol";

contract LidoCurveConvexStrategy is IStrategy {
    address public immutable master;

    address public constant Contract_Lido_stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant Contract_Curve_ETH_stETH_Pool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant Contrace_Convex_Booster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    address public constant Token_steCRV = 0x06325440D014e39736583c165C2963BA99fAf14E;
    address public constant Token_LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address public constant Token_CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant Token_CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    address public constant Token_cvxCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;


    uint256 public constant Convex_steCRV_Pool_Id = 25;

    modifier onlyMaster() {
        require(msg.sender == master, "only master");
        _;
    }

    constructor(address _master) {
        master = _master;
    }

    receive() external payable {}

    function identifier() external pure returns(bytes32) { return keccak256("LidoCurveConvexStrategy"); }

    function invest(bytes calldata params) public override payable onlyMaster{
        (params); // to supress compile warning
        require(msg.value > 0, "should pay eth");

        (bool success, bytes memory result) = Contract_Curve_ETH_stETH_Pool.call{value: msg.value}(
            abi.encodeWithSignature("add_liquidity(uint256[2],uint256)", [msg.value, 0], 0)
        );
        require(success, string(result));

        // approve
        IConvex convex = IConvex(Contrace_Convex_Booster);
        IConvex.PoolInfo memory poolInfo = convex.poolInfo(Convex_steCRV_Pool_Id);
        IERC20 steCRV = IERC20(poolInfo.lptoken);
        uint256 balance = steCRV.balanceOf(address(this));
        console.log("invest [%s, %s]: %s", poolInfo.lptoken, address(this), balance);
        steCRV.approve(Contrace_Convex_Booster, balance);
        // // deposit to convex
        convex.depositAll(Convex_steCRV_Pool_Id, true);

         uint256 userBal = IERC20(poolInfo.token).balanceOf(address(this));
         console.log("poolInfo.token: %s", userBal);
    }

    function recall(address recipient) public override onlyMaster {
        IConvex convex = IConvex(Contrace_Convex_Booster);
        IConvex.PoolInfo memory poolInfo = convex.poolInfo(Convex_steCRV_Pool_Id);
        // 1. remove staking from convex
        IConvexRewards rewards = IConvexRewards(poolInfo.crvRewards);
        rewards.withdrawAll(true);

        // 2. withdraw lptoken from Convex
        convex.withdrawAll(Convex_steCRV_Pool_Id);

        // 3. remove liquidity from Curve
        IERC20 steCRV = IERC20(poolInfo.lptoken);
        uint256 steCRVBalance = steCRV.balanceOf(address(this));
        console.log("recall [%s, %s]: %s", poolInfo.lptoken, address(this), steCRVBalance);

        // 3.1 calculate the min amount
        (bool success, bytes memory result) = Contract_Curve_ETH_stETH_Pool.staticcall(
            abi.encodeWithSignature("calc_withdraw_one_coin(uint256,int128)", steCRVBalance, 0)
        );
        require(success, string(result));
        // 3.2 remove liquidity from Curve
        uint256 minAmount = abi.decode(result, (uint256));
        console.log("minAmount: %s", minAmount);
        (success, result) = Contract_Curve_ETH_stETH_Pool.call(
            abi.encodeWithSignature(
                "remove_liquidity_one_coin(uint256,int128,uint256)",
                steCRVBalance,
                0,
                minAmount
            )
        );
        require(success, string(result));
        // 4. exchange all rewards to ETH
        exchangeRewards(poolInfo);

        // 5. send all balance of ETH to recipient
        console.log("now balance of this: %s", address(this).balance);
        payable(recipient).transfer(address(this).balance);
    }

    function exchangeRewards(IConvex.PoolInfo memory poolInfo) internal {
        // 1. exchange stETH to ETH
        IERC20 stETH = IERC20(Contract_Lido_stETH);
        // uint256 stETHBalance = stETH.balanceOf(address(this));

        // // 1.1 approve curve pool to operate stETH
        // stETH.approve(Contract_Curve_ETH_stETH_Pool, stETHBalance);

        // // 1.2. to estimate how many ETH return back.
        // (bool success, bytes memory result) = Contract_Curve_ETH_stETH_Pool.staticcall(
        //     abi.encodeWithSignature("get_dy(int128,int128,uint256)", 1, 0, stETHBalance)
        // );
        // require(success, string(result));

        // // 1.3 do exchange
        // uint256 min_dy = abi.decode(result, (uint256));
        // (success, result) = Contract_Curve_ETH_stETH_Pool.call{value: 0}(
        //     abi.encodeWithSignature(
        //         "exchange(int128,int128,uint256,int256)",
        //         1,
        //         0,
        //         stETHBalance,
        //         type(uint256).max
        //     )
        // );
        // if (!success) {
        //     string memory s = _getRevertMsg(result);
        //     console.log("exchange failed: %s", s);
        // } else {
        //     console.log("exchange success");
        // }
        // require(success, string(result));

        IERC20 crvRewards = IERC20(poolInfo.crvRewards);
        uint256 crvRewardsBalance = crvRewards.balanceOf(address(this));

        IERC20 lido = IERC20(Token_LDO);
        IERC20 crv = IERC20(Token_CRV);
        IERC20 cvx = IERC20(Token_CVX);
        IERC20 cvxCRV = IERC20(Token_cvxCRV);

        console.log("crvRewards: %s", crvRewardsBalance);
        console.log("lido: %s", lido.balanceOf(address(this)));
        console.log("crv: %s", crv.balanceOf(address(this)));
        console.log("cvx: %s", cvx.balanceOf(address(this)));
        console.log("cvxCRV: %s", cvxCRV.balanceOf(address(this)));
        console.log("stETH: %s", stETH.balanceOf(address(this)));
    }

    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
    // If the _res length is less than 68, then the transaction failed silently (without a revert message)
    if (_returnData.length < 68) return 'Transaction reverted silently';

    assembly {
        // Slice the sighash.
        _returnData := add(_returnData, 0x04)
    }
    return abi.decode(_returnData, (string)); // All that remains is the revert string
}
}