import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("EscrowContract", (m) => {
  // Get the deployer account
  const deployer = m.getAccount(0);
  
  // For testing purposes, we'll use the deployer for all roles
  // In production, these should be different addresses
  const government = m.getAccount(1);
  const pauser = m.getAccount(2);

  // Deploy TenderContract first
  const tenderContract = m.contract("TenderContract", [
    deployer, // defaultAdmin
    government, // government
    pauser, // pauser
    deployer // platformWallet
  ]);

  // Deploy EscrowContract
  const escrowContract = m.contract("EscrowContract", [
    deployer, // defaultAdmin
    government, // government
    pauser, // pauser
    tenderContract // tenderContract
  ]);

  return { tenderContract, escrowContract };
});
