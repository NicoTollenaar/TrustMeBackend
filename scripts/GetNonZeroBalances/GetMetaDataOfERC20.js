// This script demonstrates access to the core API via the Alchemy SDK.

const { Network, Alchemy } = require("alchemy-sdk");
require("dotenv").config();

// Optional Config object, but defaults to demo api-key and eth-mainnet.
const settings = {
    apiKey: `${process.env.ALCHEMY_API_KEY_MAINNET}`, // Replace with your Alchemy API Key.
    network: Network.ETH_MAINNET, // Replace with your network.
};

const alchemy = new Alchemy(settings);


async function getMetDataForERC20() {
    

// Fetch metadata for a particular ERC20 token:

const hardCodedTokenAddress = "0xe4bceb2ed4b4c43f04a9fd1e0e7046a45ef1cd41";

const TokenAddress = process.argv[2] || hardCodedTokenAddress;

console.log("fetching metadata for token with contract address: ", TokenAddress);

const response = await alchemy.core.getTokenMetadata(
  TokenAddress);

console.log("response:", response);

console.log("===");

}

getMetDataForERC20();