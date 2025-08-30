import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("BidSubmissionContract", (m) => {
  // Get the deployer account
  const deployer = m.getAccount(0);
  
  // For testing purposes, we'll use the deployer for all roles
  // In production, these should be different addresses
  const government = m.getAccount(0);
  const pauser = m.getAccount(0);
  const platformWallet = m.getAccount(0);

  // Deploy TenderContract first
  const tenderContract = m.contract("TenderContract", [
    deployer, // defaultAdmin
    government, // government
    pauser, // pauser
    platformWallet // platformWallet
  ]);

  // Deploy BidSubmissionContract
  const bidSubmissionContract = m.contract("BidSubmissionContract", [
    deployer, // defaultAdmin
    government, // government
    pauser, // pauser
    platformWallet, // platformWallet
    tenderContract // tenderContract
  ]);

  // Grant BID_SUBMISSION_ROLE to BidSubmissionContract
  m.call(tenderContract, "grantBidSubmissionRole", [bidSubmissionContract]);

  return { tenderContract, bidSubmissionContract };
});
