const hre = require("hardhat");

const NEOSAFE = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");

  const deployed = {};

  // Phase 1: Core infrastructure (no dependencies)
  console.log("\n--- Phase 1: Core Infrastructure ---");

  deployed.OpenMatrixDID = await deploy("OpenMatrixDID");
  deployed.OpenMatrixNFT = await deploy("OpenMatrixNFT");
  deployed.StablecoinTransfer = await deploy("StablecoinTransfer");
  deployed.LoyaltyRewards = await deploy("LoyaltyRewards");
  deployed.OpenMatrixStaking = await deploy("OpenMatrixStaking");
  deployed.SecurityToken = await deploy("SecurityToken");

  // Phase 2: Governance & DAO
  console.log("\n--- Phase 2: Governance & DAO ---");

  deployed.OpenMatrixGovernance = await deploy("OpenMatrixGovernance");
  deployed.OpenMatrixDAO = await deploy("OpenMatrixDAO");

  // Phase 3: Dispute Resolution (needed by many components)
  console.log("\n--- Phase 3: Dispute Resolution ---");

  deployed.DisputeResolution = await deploy("DisputeResolution");

  // Phase 4: Financial contracts
  console.log("\n--- Phase 4: Financial Contracts ---");

  deployed.ContractConversion = await deploy("ContractConversion");
  deployed.DeFiLoan = await deploy("DeFiLoan");
  deployed.P2PLoan = await deploy("P2PLoan");
  deployed.SecurityExchange = await deploy("SecurityExchange");

  // Phase 5: NFT & IP
  console.log("\n--- Phase 5: NFT & IP ---");

  deployed.NFTRights = await deploy("NFTRights");
  deployed.RoyaltyEnforcement = await deploy("RoyaltyEnforcement");
  deployed.IPRegistry = await deploy("IPRegistry");

  // Phase 6: Property & Supply Chain
  console.log("\n--- Phase 6: Property & Supply Chain ---");

  deployed.JointOwnership = await deploy("JointOwnership");
  deployed.SupplyChain = await deploy("SupplyChain");

  // Phase 7: Insurance (depends on oracle)
  console.log("\n--- Phase 7: Insurance ---");

  // Oracle address placeholder — set after Component 11 is live
  const oracleAddress = process.env.ORACLE_ADDRESS || deployer.address;
  deployed.ParametricInsurance = await deploy("ParametricInsurance", [oracleAddress]);

  // Phase 8: Gaming
  console.log("\n--- Phase 8: Gaming ---");

  deployed.GameRegistry = await deploy("GameRegistry");
  deployed.GameFunding = await deploy("GameFunding");
  deployed.GameRevenue = await deploy("GameRevenue");
  deployed.GameAsset = await deploy("GameAsset");

  // Phase 9: Marketplace & Social
  console.log("\n--- Phase 9: Marketplace & Social ---");

  deployed.Marketplace = await deploy("Marketplace");
  deployed.CommunityFundraising = await deploy("CommunityFundraising");
  deployed.SocialPost = await deploy("SocialPost");

  // Phase 10: Rewards & Subscriptions
  console.log("\n--- Phase 10: Rewards & Subscriptions ---");

  deployed.PowerUserCashback = await deploy("PowerUserCashback");
  deployed.BrandRewards = await deploy("BrandRewards");
  deployed.SubscriptionRewards = await deploy("SubscriptionRewards");

  // Phase 11: Privacy (deployed last — irrevocable commitment)
  console.log("\n--- Phase 11: Privacy (Irrevocable) ---");

  deployed.PrivacyProtection = await deploy("PrivacyProtection");

  // Summary
  console.log("\n=== Deployment Summary ===");
  console.log("NeoSafe:", NEOSAFE);
  for (const [name, contract] of Object.entries(deployed)) {
    console.log(`${name}: ${contract.target}`);
  }
  console.log(`\nTotal contracts deployed: ${Object.keys(deployed).length}`);
}

async function deploy(name, args = []) {
  process.stdout.write(`  Deploying ${name}...`);
  const factory = await hre.ethers.getContractFactory(name);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  console.log(` ${contract.target}`);
  return contract;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
