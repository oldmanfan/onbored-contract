import { expect } from "chai";
import { ethers } from "hardhat";

async function ForwardBlocks(blocks: number) {
    await ethers.provider.send("hardhat_mine", [`0x${blocks.toString(16)}`]);
}

describe("OnBored", function() {

    it("invest", async () => {
        let [player1, player2] = await ethers.getSigners();

        let OnBored = await ethers.getContractFactory("OnBored");
        let onbored = await OnBored.deploy();
        await onbored.deployed();

        let Strategy = await ethers.getContractFactory("LidoCurveConvexStrategy");
        let strategy = await Strategy.deploy(onbored.address);
        await strategy.deployed();

        await onbored.registerStrategy(strategy.address);

        let sid = await strategy.identifier();
        await onbored.connect(player1).invest(sid, ethers.utils.formatBytes32String("nothing"), {value: ethers.utils.parseEther("1.3")});

        // await ForwardBlocks(7 * 86400 / 15); // forward 7 days

        console.log(`player1 balance before: ${await ethers.provider.getBalance(player1.address)}`)
        await onbored.connect(player1).recall(sid);
        console.log(`player1 balance after:  ${await ethers.provider.getBalance(player1.address)}`)

    })
});