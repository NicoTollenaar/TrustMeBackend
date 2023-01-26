// This script demonstrates access to the NFT API via the Alchemy SDK.

const { Network, Alchemy } = require("alchemy-sdk");
require("dotenv").config();

// Optional Config object, but defaults to demo api-key and eth-mainnet.
const settings = {
    apiKey: `${process.env.ALCHEMY_API_KEY_MAINNET}`, // Replace with your Alchemy API Key.
    network: Network.ETH_MAINNET, // Replace with your network.
};

const alchemy = new Alchemy(settings);


async function getMetDataForNFT() {
    

// Fetch metadata for a particular NFT:

const hardCodedNFTAddress = "0x5180db8F5c931aaE63c74266b211F580155ecac8";
const hardCodedTokenId = "1590";

const NFTAddress = process.argv[2] || hardCodedNFTAddress;
const TokenId = process.argv[3] || hardCodedTokenId;

console.log("fetching metadata for NFT with contract address: ", NFTAddress);

const response = await alchemy.nft.getNftMetadata(
  NFTAddress,
  TokenId
);

console.log("response:", response);

console.log("===");

}

getMetDataForNFT();