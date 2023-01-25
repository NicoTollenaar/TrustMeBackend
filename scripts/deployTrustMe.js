const {ethers} = require("hardhat");
const artifacts = require("../artifacts/contracts/TrustMe.sol/TrustMe.json");
require("dotenv").config();

async function deploy(){
    try {
        const provider = new ethers.providers.JsonRpcProvider(process.env.ALCHEMY_GOERLI_URL);
        const wallet = new ethers.Wallet(process.env.GOERLI_PRIVATE_KEY, provider);
        const factory = new ethers.ContractFactory(artifacts.abi, artifacts.bytecode, wallet);
        const contract = await factory.deploy();
        await contract.deployTransaction.wait();
        console.log("Deployed at address:", contract.address); 
    } catch (error) {
        console.log(error)
    }
}

deploy();