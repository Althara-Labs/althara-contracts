import { expect } from "chai";
import { TenderContract } from "../types/ethers-contracts/index.js";

// Access ethers from the hardhat runtime environment
const hardhat = await import("hardhat");
const ethers = (hardhat as any).ethers || (hardhat as any).default?.ethers;

describe("TenderContract", function () {
  let tenderContract: TenderContract;
  let owner: any;
  let government: any;
  let pauser: any;
  let platformWallet: any;
  let bidder: any;
  let addr1: any;

  beforeEach(async function () {
    [owner, government, pauser, platformWallet, bidder, addr1] = await ethers.getSigners();

    const TenderContract = await ethers.getContractFactory("TenderContract");
    tenderContract = await TenderContract.deploy(
      owner.address,
      government.address,
      pauser.address,
      platformWallet.address
    );
  });

  describe("Deployment", function () {
    it("Should set the correct roles", async function () {
      expect(await tenderContract.hasRole(await tenderContract.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
      expect(await tenderContract.hasRole(await tenderContract.GOVERNMENT_ROLE(), government.address)).to.be.true;
      expect(await tenderContract.hasRole(await tenderContract.PAUSER_ROLE(), pauser.address)).to.be.true;
    });

    it("Should set the correct platform wallet", async function () {
      expect(await tenderContract.platformWallet()).to.equal(platformWallet.address);
    });

    it("Should set the correct service fee", async function () {
      expect(await tenderContract.serviceFee()).to.equal(ethers.parseEther("0.01"));
    });
  });

  describe("Tender Creation", function () {
    it("Should allow government to create a tender", async function () {
      const description = "Road construction project";
      const budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      const initialBalance = await ethers.provider.getBalance(platformWallet.address);

      await expect(
        tenderContract.connect(government).createTender(description, budget, requirementsCid, {
          value: serviceFee
        })
      )
        .to.emit(tenderContract, "TenderCreated")
        .withArgs(1, government.address, description, budget);

      const [tenderDesc, tenderBudget, tenderCid, completed, bidIds] = await tenderContract.getTenderDetails(1);
      expect(tenderDesc).to.equal(description);
      expect(tenderBudget).to.equal(budget);
      expect(tenderCid).to.equal(requirementsCid);
      expect(completed).to.be.false;
      expect(bidIds).to.deep.equal([]);

      const finalBalance = await ethers.provider.getBalance(platformWallet.address);
      expect(finalBalance - initialBalance).to.equal(serviceFee);
    });

    it("Should revert if non-government tries to create tender", async function () {
      const description = "Road construction project";
      const budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await expect(
        tenderContract.connect(bidder).createTender(description, budget, requirementsCid, {
          value: serviceFee
        })
      ).to.be.revertedWithCustomError(tenderContract, "AccessControlUnauthorizedAccount");
    });

    it("Should revert if insufficient service fee is paid", async function () {
      const description = "Road construction project";
      const budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const insufficientFee = ethers.parseEther("0.005");

      await expect(
        tenderContract.connect(government).createTender(description, budget, requirementsCid, {
          value: insufficientFee
        })
      ).to.be.revertedWithCustomError(tenderContract, "InsufficientServiceFee");
    });
  });

  describe("Tender Management", function () {
    beforeEach(async function () {
      const description = "Road construction project";
      const budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });
    });

    it("Should allow government to mark tender as complete", async function () {
      await expect(tenderContract.connect(government).markTenderComplete(1))
        .to.emit(tenderContract, "TenderCompleted")
        .withArgs(1);

      const [, , , completed] = await tenderContract.getTenderDetails(1);
      expect(completed).to.be.true;
    });

    it("Should revert if non-government tries to mark tender complete", async function () {
      await expect(
        tenderContract.connect(bidder).markTenderComplete(1)
      ).to.be.revertedWithCustomError(tenderContract, "AccessControlUnauthorizedAccount");
    });

    it("Should revert if trying to mark already completed tender", async function () {
      await tenderContract.connect(government).markTenderComplete(1);
      
      await expect(
        tenderContract.connect(government).markTenderComplete(1)
      ).to.be.revertedWithCustomError(tenderContract, "TenderAlreadyCompleted");
    });

    it("Should return correct tender count", async function () {
      expect(await tenderContract.getTenderCount()).to.equal(1);
    });

    it("Should return correct tender info", async function () {
      const [description, budget, requirementsCid, completed, bidIds, creator, createdAt] = 
        await tenderContract.getTenderInfo(1);
      
      expect(description).to.equal("Road construction project");
      expect(budget).to.equal(ethers.parseEther("1000000"));
      expect(requirementsCid).to.equal("QmTestRequirementsCID");
      expect(completed).to.be.false;
      expect(bidIds).to.deep.equal([]);
      expect(creator).to.equal(government.address);
      expect(createdAt).to.be.gt(0);
    });
  });

  describe("Bid Management", function () {
    beforeEach(async function () {
      const description = "Road construction project";
      const budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });
    });

    it("Should allow adding bids to tender", async function () {
      await expect(tenderContract.addBid(1, 100))
        .to.emit(tenderContract, "BidAdded")
        .withArgs(1, 100);

      const [, , , , bidIds] = await tenderContract.getTenderDetails(1);
      expect(bidIds).to.deep.equal([100n]);
    });

    it("Should not allow adding bids to completed tender", async function () {
      await tenderContract.connect(government).markTenderComplete(1);
      
      await expect(
        tenderContract.addBid(1, 100)
      ).to.be.revertedWithCustomError(tenderContract, "TenderAlreadyCompleted");
    });

    it("Should revert for invalid tender ID", async function () {
      await expect(
        tenderContract.addBid(999, 100)
      ).to.be.revertedWithCustomError(tenderContract, "InvalidTenderId");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow admin to update service fee", async function () {
      const newFee = ethers.parseEther("0.02");
      
      await expect(tenderContract.connect(owner).updateServiceFee(newFee))
        .to.emit(tenderContract, "ServiceFeeUpdated")
        .withArgs(newFee);

      expect(await tenderContract.serviceFee()).to.equal(newFee);
    });

    it("Should allow admin to update platform wallet", async function () {
      await expect(tenderContract.connect(owner).updatePlatformWallet(addr1.address))
        .to.emit(tenderContract, "PlatformWalletUpdated")
        .withArgs(addr1.address);

      expect(await tenderContract.platformWallet()).to.equal(addr1.address);
    });

    it("Should allow admin to grant bid submission role", async function () {
      await tenderContract.connect(owner).grantBidSubmissionRole(bidder.address);
      
      expect(await tenderContract.hasRole(await tenderContract.BID_SUBMISSION_ROLE(), bidder.address)).to.be.true;
    });

    it("Should allow admin to revoke bid submission role", async function () {
      await tenderContract.connect(owner).grantBidSubmissionRole(bidder.address);
      await tenderContract.connect(owner).revokeBidSubmissionRole(bidder.address);
      
      expect(await tenderContract.hasRole(await tenderContract.BID_SUBMISSION_ROLE(), bidder.address)).to.be.false;
    });
  });

  describe("Pausable", function () {
    it("Should allow pauser to pause and unpause", async function () {
      await tenderContract.connect(pauser).pause();
      expect(await tenderContract.paused()).to.be.true;

      await tenderContract.connect(pauser).unpause();
      expect(await tenderContract.paused()).to.be.false;
    });

    it("Should not allow non-pauser to pause", async function () {
      await expect(
        tenderContract.connect(bidder).pause()
      ).to.be.revertedWithCustomError(tenderContract, "AccessControlUnauthorizedAccount");
    });
  });
});
