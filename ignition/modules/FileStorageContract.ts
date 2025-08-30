import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("FileStorageContract", (m) => {
  // Get the deployer account
  const deployer = m.getAccount(0);
  
  // For testing purposes, we'll use the deployer for all roles
  // In production, these should be different addresses
  const government = m.getAccount(0);
  const pauser = m.getAccount(0);

  // Deploy FileStorageContract
  const fileStorageContract = m.contract("FileStorageContract", [
    deployer, // defaultAdmin
    government, // government
    pauser // pauser
  ]);

  return { fileStorageContract };
});
