import { expect } from "chai";
import { ethers } from "hardhat";
import ERC20 = require("@openzeppelin/contracts/build/contracts/ERC20.json");

describe("Common", function () {
    it("balance of convex", async () => {
       console.log('balance: ', await ethers.provider.getBalance("0x4b330F477075d810A959d8499034b0f1058826BC"))
        // let erc = new ethers.Contract("0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B", ERC20.abi);
        // console.log(`balance of : ${await erc.balanceOf("0x95a273888ce2494a817ae206e44a737a5bacda9f")}`)
    });
});