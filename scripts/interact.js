const {ethers} = require("hardhat");
const artifacts = require("../artifacts/contracts/TrustMe.sol/TrustMe.json");
const address = "0x32F9D2e5f2db3C6e463700D5A33EeE1a4cef761B";


async function interact(){
    const provider = new ethers.providers.JsonRpcProvider(process.env.ALCHEMY_GOERLI_URL);
    const signer = new ethers.Wallet(process.env.GOERLI_PRIVATE_KEY, provider);
    const contract = new ethers.Contract(address, artifacts.abi, signer);
    const chainLinkTestSuccesful = await contract.chainLinkTestSuccesful();
    const chainLinkCaller = await contract.chainLinkCaller();
    const upKeepCount = await contract.upKeepCount();
    console.log("chainLinkTestSuccesful", chainLinkTestSuccesful);
    console.log("chainLinkCaller", chainLinkCaller);
    console.log("upKeepCount", upKeepCount);
}

interact();