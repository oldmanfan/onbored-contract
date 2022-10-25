// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../IStrategy.sol";
import "./ICurve.sol";
import "./IConvex.sol";
import "./IConvexRewards.sol";

import "../exchanges/IUniswapV2Router02.sol";
import "../exchanges/IWETH9.sol";

import "hardhat/console.sol";

contract LidoCurveConvexStrategy is IStrategy {
    address public immutable master;

    address public constant Contract_Lido_stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant Contract_Curve_ETH_stETH_Pool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant Contrace_Convex_Booster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    address public constant Token_steCRV = 0x06325440D014e39736583c165C2963BA99fAf14E;
    address public constant Token_cvxCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;

    address public constant Token_LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address public constant Token_CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant Token_CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

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

    function getEarnings() external view returns(uint256) {
         IConvex convex = IConvex(Contrace_Convex_Booster);
        IConvex.PoolInfo memory poolInfo = convex.poolInfo(Convex_steCRV_Pool_Id);

        IERC20 steCRV = IERC20(poolInfo.lptoken);
        uint256 steCRVBalance = steCRV.balanceOf(address(this));

        (bool success, bytes memory result) = Contract_Curve_ETH_stETH_Pool.staticcall(
            abi.encodeWithSignature("calc_withdraw_one_coin(uint256,int128)", steCRVBalance, 0)
        );
        if (!success) return 0;

        uint256 minAmount = abi.decode(result, (uint256));

        address[] memory tokens = new address[](3);
        tokens[0] = Token_LDO;
        tokens[1] = Token_CRV;
        tokens[2] = Token_CVX;

        uint256 earnings = minAmount + estimateRewardsEarning(tokens);
        return earnings;
    }

    function estimateRewardsEarning(address[] memory erc20Tokens) public view returns(uint256) {
        IUniswapV2Router02 router = IUniswapV2Router02(UniswapV2Router_ADDR);
        uint256 totalEarnings;
        for (uint i = 0; i < erc20Tokens.length; i++) {
            IERC20 erc20 = IERC20(erc20Tokens[i]);
            uint256 balance = erc20.balanceOf(address(this));

            if (balance > 0) {
                address[] memory paths = new address[](2);
                paths[0] = erc20Tokens[i];
                paths[1] = WETH_ADDR;

                uint256[] memory amounts = router.getAmountsOut(balance, paths);
                totalEarnings += amounts[amounts.length - 1];

                console.log("earnings %s : in %s, out: %s", erc20Tokens[i], balance, amounts[amounts.length - 1]);
            }
        }

        return totalEarnings;
    }

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
        console.log("before remove liquidity: %s", address(this).balance);
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
        console.log("before exchange this: %s", address(this).balance);
        exchangeRewards();

        // 5. send all balance of ETH to recipient
        console.log("now balance of this: %s", address(this).balance);
        payable(recipient).transfer(address(this).balance);
    }

    function exchangeRewards() internal {
        IERC20 lido = IERC20(Token_LDO);
        IERC20 crv = IERC20(Token_CRV);
        IERC20 cvx = IERC20(Token_CVX);

        console.log("lido: %s", lido.balanceOf(address(this)));
        console.log("crv: %s", crv.balanceOf(address(this)));
        console.log("cvx: %s", cvx.balanceOf(address(this)));

        address[] memory tokens = new address[](3);
        tokens[0] = Token_LDO;
        tokens[1] = Token_CRV;
        tokens[2] = Token_CVX;

        UniswapV2Exchange(tokens);

        console.log("lido2: %s", lido.balanceOf(address(this)));
        console.log("crv2: %s", crv.balanceOf(address(this)));
        console.log("cvx2: %s", cvx.balanceOf(address(this)));
    }

    address constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant UniswapV2Router_ADDR = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    function UniswapV2Exchange(address[] memory erc20Tokens) internal {
        IUniswapV2Router02 router = IUniswapV2Router02(UniswapV2Router_ADDR);
        uint256 totalSwaped;
        for (uint i = 0; i < erc20Tokens.length; i++) {
            IERC20 erc20 = IERC20(erc20Tokens[i]);
            uint256 balance = erc20.balanceOf(address(this));

            if (balance > 0) {
                erc20.approve(UniswapV2Router_ADDR, balance);

                address[] memory paths = new address[](2);
                paths[0] = erc20Tokens[i];
                paths[1] = WETH_ADDR;

                uint256[] memory amounts = router.swapExactTokensForTokens(balance, 0, paths, address(this), block.timestamp + 1 minutes);
                totalSwaped += amounts[amounts.length - 1];

                console.log("swap %s : in %s, out: %s", erc20Tokens[i], balance, amounts[amounts.length - 1]);
            }
        }

        if (totalSwaped > 0) {
            IWETH9 weth = IWETH9(WETH_ADDR);
            weth.withdraw(totalSwaped);
        }
    }
}