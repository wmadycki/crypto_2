const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Specify the arguments for the constructor here
    const name = "Die Hard";
    const symbol = "DIE";
    const supply = 1000000;
    const owner = "0xBDA17A5Af770E55e7b7Dc901B96cff488D37b77D";


    const ContractFactory = await ethers.getContractFactory("Gold");
    const contract = await ContractFactory.deploy(name, symbol, supply, { gasLimit: 5000000 });
    console.log("Contract deployed to:", contract.address);

    const receipt = await contract.deployTransaction.wait();

    const events = receipt.events || [];
    events.forEach(event => {
        console.log(`Event: ${event.event}`);
        console.log(`Args: `, event.args);
    });
}


main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
