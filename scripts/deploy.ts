import { network } from "hardhat";

async function main() {

    const connection = await network.connect();

    const ethers = connection.ethers;

    if (!ethers) {
        throw new Error("Ethers plugin not loaded. Check hardhat.config.ts");
    }

    const [buyer, seller, arbiter] = await ethers.getSigners();

    console.log("Buyer:", buyer.address);

    const EscrowFactory = await ethers.getContractFactory("TrustlessEscrow");

    const escrow = await EscrowFactory.deploy(
        seller.address,
        arbiter.address
    );

    await escrow.waitForDeployment();

    const address = await escrow.getAddress();

    console.log("Escrow deployed at:", address);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});