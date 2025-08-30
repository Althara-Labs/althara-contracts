import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("TenderContract", (m) => {
  // Get the deployer account
  const deployer = m.getAccount(0);
  
  // For deployment purposes, we'll use the deployer for all roles
  // In production, these should be different addresses
  const government = m.getAccount(0); // Use same account as deployer
  const pauser = m.getAccount(0); // Use same account as deployer
  const platformWallet = m.getAccount(0); // Use same account as deployer

  const tenderContract = m.contract("TenderContract", [
    deployer, // defaultAdmin
    government, // government
    pauser, // pauser
    platformWallet // platformWallet
  ]);

  return { tenderContract };
});
