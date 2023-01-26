// This script demonstrates access to the Alchemy Core API via the Alchemy SDK.

const { Network, Alchemy } = require("alchemy-sdk");
require("dotenv").config();

// Optional Config object, but defaults to demo api-key and eth-mainnet.
const settings = {
    apiKey: `${process.env.ALCHEMY_API_KEY_MAINNET}`, // Replace with your Alchemy API Key.
    network: Network.ETH_MAINNET, // Replace with your network.
};

const alchemy = new Alchemy(settings);


async function getERC20BalancesForAddress() {
    const hardCodedOwnerAddress = "0xshah.eth";
    const ownerAddr = process.argv[2] || hardCodedOwnerAddress;

    console.log("fetching ERC20 balances for address:", ownerAddr);
    console.log("...");

// Print total NFT count returned in the response:
const response = await alchemy.core.getTokenBalances(ownerAddr);

console.log("response:", response);

console.log("===");

}

getERC20BalancesForAddress();