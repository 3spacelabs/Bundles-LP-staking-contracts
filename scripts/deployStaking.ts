import { ethers, run, network } from "hardhat";


function delay(ms: number) {
    console.log("Sleeping for", ms / 1000, "seconds...\n")
    return new Promise( resolve => setTimeout(resolve, ms) );
}

async function deploy() {
    const reward_amounts = ["500", "750", "1000"];
    const durations = [5184000, 7776000, 15552000];
    const names = ['60 day lock', '90 day lock', '180 day lock']

    const START_TIME = 1732665600 // Math.round(Date.now() / 1000) + 300; // 5 minutes from now while txns propagate
    console.log("Start Time set to:", START_TIME);

    const stakingToken_address = '0xeFbe61Cd97eD5419e435Da5C6b14d0C982653826';
    const rewardToken_address = '0x47dae46d31f31f84336ac120b15efda261d484fb';
    const routerAddress = '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff';
    const WETHAddress = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270';

    const bundToken = await ethers.getContractAt("IERC20", rewardToken_address);
    const stakingFactory = await ethers.getContractFactory("BUNDLPStaking");

    const [deployer] = await ethers.getSigners();
    const provider = ethers.getDefaultProvider("matic");
    const balance = await provider.getBalance(deployer.address);

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", ethers.formatEther(balance.toString()), "$MATIC\n");
    await delay(10000);
    
    var pools = [];

    for (var i = 0; i < reward_amounts.length; i++) {
        // const staking = stakingFactory.attach('0x4145022F552F1055F00e756aE1E4C231c666caF6');
        var REWARD_AMOUNT = ethers.parseEther(reward_amounts[i]);
        var STOP_TIME = START_TIME + durations[i];
        var POOL_NAME = names[i];

        const staking = await stakingFactory.deploy(
            stakingToken_address,
            rewardToken_address,
            REWARD_AMOUNT,
            START_TIME,
            STOP_TIME,
            routerAddress,
            WETHAddress
        );

        var stakingPoolAddress = await staking.getAddress();
        console.log("\nDeployed a staking pool:", stakingPoolAddress);
        await delay(10000);  // Sleep for 10s to allow for txn to propagate

        // Approve the staking address to move tokens from the deployer
        console.log("Approving contract to pull BUND")
        await bundToken.approve(stakingPoolAddress, REWARD_AMOUNT);
        await delay(10000);  // Sleep for 10s to allow for txn to propagate

        // Load reward tokens
        console.log("Loading BUND into contract")
        await staking.loadReward();
        await delay(10000);  // Sleep for 10s to allow for txn to propagate

        // Programatically verify the contracts
        try {
            await run("verify:verify", {
                address: await staking.getAddress(),
                contract: "contracts/LPStaking.sol:BUNDLPStaking",
                constructorArguments: [
                    stakingToken_address,
                    rewardToken_address,
                    REWARD_AMOUNT,
                    START_TIME,
                    STOP_TIME,
                    routerAddress,
                    WETHAddress
                ],
            });
        } catch (e: any) {
            console.error(`error in verifying: ${e.message}`);
        }

        pools.push({
            startTime: START_TIME,
            stopTime: STOP_TIME,
            rewardAmount: ethers.formatEther(REWARD_AMOUNT).toString() + " $BUND",
            staking: await staking.getAddress(),
            name: POOL_NAME
        });
    }
    console.log(pools);
}

deploy().catch((e: any) => console.log(e.message));
