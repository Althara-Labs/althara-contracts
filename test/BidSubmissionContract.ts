import { expect } from "chai";
import { BidSubmissionContract, TenderContract } from "../types/ethers-contracts/index.js";

describe("BidSubmissionContract", function () {
  let bidSubmissionContract: BidSubmissionContract;
  let tenderContract: TenderContract;
  let owner: any;
  let government: any;
  let pauser: any;
  let platformWallet: any;
  let vendor1: any;
  let vendor2: any;
  let addr1: any;

  beforeEach(async function () {
    [owner, government, pauser, platformWallet, vendor1, vendor2, addr1] = await ethers.getSigners();

    // Deploy TenderContract first
    const TenderContract = await ethers.getContractFactory("TenderContract");
    tenderContract = await TenderContract.deploy(
      owner.address,
      government.address,
      pauser.address,
      platformWallet.address
    );

    // Deploy BidSubmissionContract
    const BidSubmissionContract = await ethers.getContractFactory("BidSubmissionContract");
    bidSubmissionContract = await BidSubmissionContract.deploy(
      owner.address,
      government.address,
      pauser.address,
      platformWallet.address,
      tenderContract.target
    );

    // Grant BID_SUBMISSION_ROLE to BidSubmissionContract
    await tenderContract.grantBidSubmissionRole(bidSubmissionContract.target);
  });

  describe("Deployment", function () {
    it("Should set the correct roles", async function () {
      expect(await bidSubmissionContract.hasRole(await bidSubmissionContract.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
      expect(await bidSubmissionContract.hasRole(await bidSubmissionContract.GOVERNMENT_ROLE(), government.address)).to.be.true;
      expect(await bidSubmissionContract.hasRole(await bidSubmissionContract.PAUSER_ROLE(), pauser.address)).to.be.true;
    });

    it("Should set the correct platform wallet", async function () {
      expect(await bidSubmissionContract.platformWallet()).to.equal(platformWallet.address);
    });

    it("Should set the correct service fee", async function () {
      expect(await bidSubmissionContract.serviceFee()).to.equal(ethers.parseEther("0.005"));
    });

    it("Should set the correct tender contract", async function () {
      expect(await bidSubmissionContract.tenderContract()).to.equal(tenderContract.target);
    });
  });

  describe("Bid Submission", function () {
    let tenderId: number;

    beforeEach(async function () {
      // Create a tender first
      const description = "Road construction project";
      const budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });

      tenderId = 1;
    });

    it("Should allow vendor to submit a bid", async function () {
      const price = ethers.parseEther("800000");
      const description = "Our construction proposal";
      const proposalCid = "QmProposalCID";
      const bidServiceFee = ethers.parseEther("0.005");

      const initialBalance = await ethers.provider.getBalance(platformWallet.address);

      await expect(
        bidSubmissionContract.connect(vendor1).submitBid(tenderId, price, description, proposalCid, {
          value: bidServiceFee
        })
      )
        .to.emit(bidSubmissionContract, "BidSubmitted")
        .withArgs(1, tenderId, vendor1.address, price);

      const [bidTenderId, bidVendor, bidPrice, bidDesc, bidProposalCid, bidStatus] = 
        await bidSubmissionContract.getBidDetails(1);
      
      expect(bidTenderId).to.equal(tenderId);
      expect(bidVendor).to.equal(vendor1.address);
      expect(bidPrice).to.equal(price);
      expect(bidDesc).to.equal(description);
      expect(bidProposalCid).to.equal(proposalCid);
      expect(bidStatus).to.equal(0); // Pending

      const finalBalance = await ethers.provider.getBalance(platformWallet.address);
      expect(finalBalance - initialBalance).to.equal(bidServiceFee);
    });

    it("Should revert if insufficient service fee is paid", async function () {
      const price = ethers.parseEther("800000");
      const description = "Our construction proposal";
      const proposalCid = "QmProposalCID";
      const insufficientFee = ethers.parseEther("0.002");

      await expect(
        bidSubmissionContract.connect(vendor1).submitBid(tenderId, price, description, proposalCid, {
          value: insufficientFee
        })
      ).to.be.revertedWithCustomError(bidSubmissionContract, "InsufficientServiceFee");
    });

    it("Should revert if tender is completed", async function () {
      // Mark tender as completed
      await tenderContract.connect(government).markTenderComplete(tenderId);

      const price = ethers.parseEther("800000");
      const description = "Our construction proposal";
      const proposalCid = "QmProposalCID";
      const bidServiceFee = ethers.parseEther("0.005");

      await expect(
        bidSubmissionContract.connect(vendor1).submitBid(tenderId, price, description, proposalCid, {
          value: bidServiceFee
        })
      ).to.be.revertedWithCustomError(bidSubmissionContract, "TenderNotActive");
    });

    it("Should revert for invalid tender ID", async function () {
      const price = ethers.parseEther("800000");
      const description = "Our construction proposal";
      const proposalCid = "QmProposalCID";
      const bidServiceFee = ethers.parseEther("0.005");

      await expect(
        bidSubmissionContract.connect(vendor1).submitBid(999, price, description, proposalCid, {
          value: bidServiceFee
        })
      ).to.be.revertedWithCustomError(bidSubmissionContract, "TenderNotFound");
    });
  });

  describe("Bid Management", function () {
    let tenderId: number;
    let bidId: number;

    beforeEach(async function () {
      // Create a tender
      const description = "Road construction project";
      const budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });

      tenderId = 1;

      // Submit a bid
      const price = ethers.parseEther("800000");
      const bidDescription = "Our construction proposal";
      const proposalCid = "QmProposalCID";
      const bidServiceFee = ethers.parseEther("0.005");

      await bidSubmissionContract.connect(vendor1).submitBid(tenderId, price, bidDescription, proposalCid, {
        value: bidServiceFee
      });

      bidId = 1;
    });

    it("Should allow government to accept a bid", async function () {
      await expect(bidSubmissionContract.connect(government).acceptBid(tenderId, bidId))
        .to.emit(bidSubmissionContract, "BidAccepted")
        .withArgs(bidId, tenderId);

      const [, , , , , status] = await bidSubmissionContract.getBidDetails(bidId);
      expect(status).to.equal(1); // Accepted
    });

    it("Should allow government to reject a bid", async function () {
      await expect(bidSubmissionContract.connect(government).rejectBid(tenderId, bidId))
        .to.emit(bidSubmissionContract, "BidRejected")
        .withArgs(bidId, tenderId);

      const [, , , , , status] = await bidSubmissionContract.getBidDetails(bidId);
      expect(status).to.equal(2); // Rejected
    });

    it("Should revert if non-government tries to accept bid", async function () {
      await expect(
        bidSubmissionContract.connect(vendor1).acceptBid(tenderId, bidId)
      ).to.be.revertedWithCustomError(bidSubmissionContract, "AccessControlUnauthorizedAccount");
    });

    it("Should revert if non-government tries to reject bid", async function () {
      await expect(
        bidSubmissionContract.connect(vendor1).rejectBid(tenderId, bidId)
      ).to.be.revertedWithCustomError(bidSubmissionContract, "AccessControlUnauthorizedAccount");
    });

    it("Should revert if trying to accept already processed bid", async function () {
      await bidSubmissionContract.connect(government).acceptBid(tenderId, bidId);
      
      await expect(
        bidSubmissionContract.connect(government).acceptBid(tenderId, bidId)
      ).to.be.revertedWithCustomError(bidSubmissionContract, "BidAlreadyProcessed");
    });

    it("Should revert if trying to reject already processed bid", async function () {
      await bidSubmissionContract.connect(government).rejectBid(tenderId, bidId);
      
      await expect(
        bidSubmissionContract.connect(government).rejectBid(tenderId, bidId)
      ).to.be.revertedWithCustomError(bidSubmissionContract, "BidAlreadyProcessed");
    });

    it("Should revert for invalid bid ID", async function () {
      await expect(
        bidSubmissionContract.connect(government).acceptBid(tenderId, 999)
      ).to.be.revertedWithCustomError(bidSubmissionContract, "InvalidBidId");
    });

    it("Should revert if bid doesn't belong to tender", async function () {
      // Create another tender and bid
      const description2 = "Bridge construction project";
      const budget2 = ethers.parseEther("2000000");
      const requirementsCid2 = "QmTestRequirementsCID2";
      const serviceFee2 = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description2, budget2, requirementsCid2, {
        value: serviceFee2
      });

      const tenderId2 = 2;
      const price2 = ethers.parseEther("1500000");
      const bidDescription2 = "Our bridge proposal";
      const proposalCid2 = "QmProposalCID2";
      const bidServiceFee2 = ethers.parseEther("0.005");

      await bidSubmissionContract.connect(vendor2).submitBid(tenderId2, price2, bidDescription2, proposalCid2, {
        value: bidServiceFee2
      });

      const bidId2 = 2;

      // Try to accept bid from tender2 using tender1
      await expect(
        bidSubmissionContract.connect(government).acceptBid(tenderId, bidId2)
      ).to.be.revertedWithCustomError(bidSubmissionContract, "InvalidTenderId");
    });
  });

  describe("Bid Queries", function () {
    let tenderId: number;

    beforeEach(async function () {
      // Create a tender
      const description = "Road construction project";
      const budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });

      tenderId = 1;

      // Submit multiple bids
      const bidServiceFee = ethers.parseEther("0.005");

      await bidSubmissionContract.connect(vendor1).submitBid(
        tenderId, 
        ethers.parseEther("800000"), 
        "Vendor 1 proposal", 
        "QmProposal1", 
        { value: bidServiceFee }
      );

      await bidSubmissionContract.connect(vendor2).submitBid(
        tenderId, 
        ethers.parseEther("750000"), 
        "Vendor 2 proposal", 
        "QmProposal2", 
        { value: bidServiceFee }
      );
    });

    it("Should return correct bid count", async function () {
      expect(await bidSubmissionContract.getBidCount()).to.equal(2);
    });

    it("Should return correct bid details", async function () {
      const [bidTenderId, bidVendor, bidPrice, bidDesc, bidProposalCid, bidStatus] = 
        await bidSubmissionContract.getBidDetails(1);
      
      expect(bidTenderId).to.equal(tenderId);
      expect(bidVendor).to.equal(vendor1.address);
      expect(bidPrice).to.equal(ethers.parseEther("800000"));
      expect(bidDesc).to.equal("Vendor 1 proposal");
      expect(bidProposalCid).to.equal("QmProposal1");
      expect(bidStatus).to.equal(0); // Pending
    });

    it("Should return correct bid info with timestamp", async function () {
      const [bidTenderId, bidVendor, bidPrice, bidDesc, bidProposalCid, bidStatus, submittedAt] = 
        await bidSubmissionContract.getBidInfo(1);
      
      expect(bidTenderId).to.equal(tenderId);
      expect(bidVendor).to.equal(vendor1.address);
      expect(bidPrice).to.equal(ethers.parseEther("800000"));
      expect(bidDesc).to.equal("Vendor 1 proposal");
      expect(bidProposalCid).to.equal("QmProposal1");
      expect(bidStatus).to.equal(0); // Pending
      expect(submittedAt).to.be.gt(0);
    });

    it("Should return correct tender bids", async function () {
      const tenderBids = await bidSubmissionContract.getTenderBids(tenderId);
      expect(tenderBids).to.deep.equal([1n, 2n]);
    });

    it("Should return correct vendor bids", async function () {
      const vendor1Bids = await bidSubmissionContract.getVendorBids(vendor1.address);
      expect(vendor1Bids).to.deep.equal([1n]);

      const vendor2Bids = await bidSubmissionContract.getVendorBids(vendor2.address);
      expect(vendor2Bids).to.deep.equal([2n]);
    });

    it("Should return correct bid status string", async function () {
      expect(await bidSubmissionContract.getBidStatusString(1)).to.equal("Pending");
      
      await bidSubmissionContract.connect(government).acceptBid(tenderId, 1);
      expect(await bidSubmissionContract.getBidStatusString(1)).to.equal("Accepted");
      
      await bidSubmissionContract.connect(government).rejectBid(tenderId, 2);
      expect(await bidSubmissionContract.getBidStatusString(2)).to.equal("Rejected");
    });

    it("Should return correct bid existence check", async function () {
      expect(await bidSubmissionContract.bidExists(1)).to.be.true;
      expect(await bidSubmissionContract.bidExists(2)).to.be.true;
      expect(await bidSubmissionContract.bidExists(999)).to.be.false;
    });
  });

  describe("Admin Functions", function () {
    it("Should allow admin to update service fee", async function () {
      const newFee = ethers.parseEther("0.01");
      
      await expect(bidSubmissionContract.connect(owner).updateServiceFee(newFee))
        .to.emit(bidSubmissionContract, "ServiceFeeUpdated")
        .withArgs(newFee);

      expect(await bidSubmissionContract.serviceFee()).to.equal(newFee);
    });

    it("Should allow admin to update platform wallet", async function () {
      await expect(bidSubmissionContract.connect(owner).updatePlatformWallet(addr1.address))
        .to.emit(bidSubmissionContract, "PlatformWalletUpdated")
        .withArgs(addr1.address);

      expect(await bidSubmissionContract.platformWallet()).to.equal(addr1.address);
    });

    it("Should allow admin to update tender contract", async function () {
      await expect(bidSubmissionContract.connect(owner).updateTenderContract(addr1.address))
        .to.emit(bidSubmissionContract, "TenderContractUpdated")
        .withArgs(addr1.address);

      expect(await bidSubmissionContract.tenderContract()).to.equal(addr1.address);
    });
  });

  describe("Pausable", function () {
    it("Should allow pauser to pause and unpause", async function () {
      await bidSubmissionContract.connect(pauser).pause();
      expect(await bidSubmissionContract.paused()).to.be.true;

      await bidSubmissionContract.connect(pauser).unpause();
      expect(await bidSubmissionContract.paused()).to.be.false;
    });

    it("Should not allow non-pauser to pause", async function () {
      await expect(
        bidSubmissionContract.connect(vendor1).pause()
      ).to.be.revertedWithCustomError(bidSubmissionContract, "AccessControlUnauthorizedAccount");
    });
  });
});
