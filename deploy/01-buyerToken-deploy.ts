import { HardhatRuntimeEnvironment as hre } from "hardhat/types";
import { getNamedAccounts, deployments } from "hardhat";
const deployTrustMe = async () => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    await deploy("BuyerToken", {
        from: deployer,
        args: [],
        log: true,
    });
};
export default deployTrustMe;
deployTrustMe.tags = ["BuyerToken", "all"];
