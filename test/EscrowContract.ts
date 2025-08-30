import { expect } from "chai";
import { EscrowContract, TenderContract } from "../types/ethers-contracts/index.js";

describe("EscrowContract", function () {
  let escrowContract: EscrowContract;
  let tenderContract: TenderContract;
  let owner: any;
  let government: any;
  let pauser: any;
  let vendor: any;
  let addr1: any;

  beforeEach(async function () {
    [owner, government, pauser, vendor, addr1] = await ethers.getSigners();

    // Deploy TenderContract first
    const TenderContract = await ethers.getContractFactory("TenderContract");
    tenderContract = await TenderContract.deploy(
      owner.address,
      government.address,
      pauser.address,
      owner.address // platformWallet
    );

    // Deploy EscrowContract
    const EscrowContract = await ethers.getContractFactory("EscrowContract");
    escrowContract = await EscrowContract.deploy(
      owner.address,
      government.address,
      pauser.address,
      tenderContract.target
    );
  });

  describe("Deployment", function () {
    it("Should set the correct roles", async function () {
      expect(await escrowContract.hasRole(await escrowContract.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
      expect(await escrowContract.hasRole(await escrowContract.GOVERNMENT_ROLE(), government.address)).to.be.true;
      expect(await escrowContract.hasRole(await escrowContract.PAUSER_ROLE(), pauser.address)).to.be.true;
    });

    it("Should set the correct tender contract", async function () {
      expect(await escrowContract.tenderContract()).to.equal(tenderContract.target);
    });

    it("Should have zero initial balance", async function () {
      expect(await escrowContract.getContractBalance()).to.equal(0);
    });
  });

  describe("Fund Deposits", function () {
    let tenderId: number;
    let budget: bigint;

    beforeEach(async function () {
      // Create a tender first
      const description = "Road construction project";
      budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });

      tenderId = 1;
    });

    it("Should allow government to deposit funds", async function () {
      const initialBalance = await ethers.provider.getBalance(escrowContract.target);

      await expect(
        escrowContract.connect(government).depositFunds(tenderId, {
          value: budget
        })
      )
        .to.emit(escrowContract, "FundsDeposited")
        .withArgs(tenderId, budget, government.address);

      const finalBalance = await ethers.provider.getBalance(escrowContract.target);
      expect(finalBalance - initialBalance).to.equal(budget);

      const [amount, depositor, released, depositedAt, releasedTo, releasedAt] = 
        await escrowContract.getEscrowBalance(tenderId);
      
      expect(amount).to.equal(budget);
      expect(depositor).to.equal(government.address);
      expect(released).to.be.false;
      expect(depositedAt).to.be.gt(0);
      expect(releasedTo).to.equal(ethers.ZeroAddress);
      expect(releasedAt).to.equal(0);
    });

    it("Should revert if non-government tries to deposit funds", async function () {
      await expect(
        escrowContract.connect(vendor).depositFunds(tenderId, {
          value: budget
        })
      ).to.be.revertedWithCustomError(escrowContract, "AccessControlUnauthorizedAccount");
    });

    it("Should revert if deposit amount doesn't match tender budget", async function () {
      const wrongAmount = ethers.parseEther("500000");

      await expect(
        escrowContract.connect(government).depositFunds(tenderId, {
          value: wrongAmount
        })
      ).to.be.revertedWithCustomError(escrowContract, "InvalidAmount");
    });

    it("Should revert if deposit amount is zero", async function () {
      await expect(
        escrowContract.connect(government).depositFunds(tenderId, {
          value: 0
        })
      ).to.be.revertedWithCustomError(escrowContract, "InvalidAmount");
    });

    it("Should revert if tender is completed", async function () {
      // Mark tender as completed
      await tenderContract.connect(government).markTenderComplete(tenderId);

      await expect(
        escrowContract.connect(government).depositFunds(tenderId, {
          value: budget
        })
      ).to.be.revertedWithCustomError(escrowContract, "TenderNotActive");
    });

    it("Should revert for invalid tender ID", async function () {
      await expect(
        escrowContract.connect(government).depositFunds(999, {
          value: budget
        })
      ).to.be.revertedWithCustomError(escrowContract, "TenderNotFound");
    });

    it("Should revert if escrow already exists", async function () {
      // Deposit funds first
      await escrowContract.connect(government).depositFunds(tenderId, {
        value: budget
      });

      // Try to deposit again
      await expect(
        escrowContract.connect(government).depositFunds(tenderId, {
          value: budget
        })
      ).to.be.revertedWithCustomError(escrowContract, "EscrowAlreadyReleased");
    });
  });

  describe("Fund Releases", function () {
    let tenderId: number;
    let budget: bigint;

    beforeEach(async function () {
      // Create a tender
      const description = "Road construction project";
      budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });

      tenderId = 1;

      // Deposit funds
      await escrowContract.connect(government).depositFunds(tenderId, {
        value: budget
      });
    });

    it("Should allow government to release funds after tender completion", async function () {
      // Mark tender as completed
      await tenderContract.connect(government).markTenderComplete(tenderId);

      const initialVendorBalance = await ethers.provider.getBalance(vendor.address);
      const initialContractBalance = await escrowContract.getContractBalance();

      await expect(
        escrowContract.connect(government).releaseFunds(tenderId, vendor.address)
      )
        .to.emit(escrowContract, "FundsReleased")
        .withArgs(tenderId, vendor.address, budget);

      const finalVendorBalance = await ethers.provider.getBalance(vendor.address);
      const finalContractBalance = await escrowContract.getContractBalance();

      expect(finalVendorBalance - initialVendorBalance).to.equal(budget);
      expect(initialContractBalance - finalContractBalance).to.equal(budget);

      const [, , released, , releasedTo, releasedAt] = 
        await escrowContract.getEscrowBalance(tenderId);
      
      expect(released).to.be.true;
      expect(releasedTo).to.equal(vendor.address);
      expect(releasedAt).to.be.gt(0);
    });

    it("Should revert if non-government tries to release funds", async function () {
      await tenderContract.connect(government).markTenderComplete(tenderId);

      await expect(
        escrowContract.connect(vendor).releaseFunds(tenderId, vendor.address)
      ).to.be.revertedWithCustomError(escrowContract, "AccessControlUnauthorizedAccount");
    });

    it("Should revert if tender is not completed", async function () {
      await expect(
        escrowContract.connect(government).releaseFunds(tenderId, vendor.address)
      ).to.be.revertedWithCustomError(escrowContract, "TenderNotCompleted");
    });

    it("Should revert if escrow doesn't exist", async function () {
      await tenderContract.connect(government).markTenderComplete(tenderId);

      await expect(
        escrowContract.connect(government).releaseFunds(999, vendor.address)
      ).to.be.revertedWithCustomError(escrowContract, "EscrowNotFound");
    });

    it("Should revert if funds already released", async function () {
      await tenderContract.connect(government).markTenderComplete(tenderId);

      // Release funds first
      await escrowContract.connect(government).releaseFunds(tenderId, vendor.address);

      // Try to release again
      await expect(
        escrowContract.connect(government).releaseFunds(tenderId, vendor.address)
      ).to.be.revertedWithCustomError(escrowContract, "EscrowAlreadyReleased");
    });

    it("Should revert if vendor address is zero", async function () {
      await tenderContract.connect(government).markTenderComplete(tenderId);

      await expect(
        escrowContract.connect(government).releaseFunds(tenderId, ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(escrowContract, "InvalidTenderId");
    });
  });

  describe("Fund Refunds", function () {
    let tenderId: number;
    let budget: bigint;

    beforeEach(async function () {
      // Create a tender
      const description = "Road construction project";
      budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });

      tenderId = 1;

      // Deposit funds
      await escrowContract.connect(government).depositFunds(tenderId, {
        value: budget
      });
    });

    it("Should allow government to refund funds if tender not completed", async function () {
      const initialGovernmentBalance = await ethers.provider.getBalance(government.address);
      const initialContractBalance = await escrowContract.getContractBalance();

      await expect(
        escrowContract.connect(government).refundFunds(tenderId)
      )
        .to.emit(escrowContract, "FundsRefunded")
        .withArgs(tenderId, government.address, budget);

      const finalGovernmentBalance = await ethers.provider.getBalance(government.address);
      const finalContractBalance = await escrowContract.getContractBalance();

      expect(finalGovernmentBalance - initialGovernmentBalance).to.equal(budget);
      expect(initialContractBalance - finalContractBalance).to.equal(budget);

      const [amount, depositor, released, depositedAt, releasedTo, releasedAt] = 
        await escrowContract.getEscrowBalance(tenderId);
      
      expect(amount).to.equal(0);
      expect(depositor).to.equal(ethers.ZeroAddress);
      expect(released).to.be.false;
      expect(depositedAt).to.equal(0);
      expect(releasedTo).to.equal(ethers.ZeroAddress);
      expect(releasedAt).to.equal(0);
    });

    it("Should revert if non-government tries to refund funds", async function () {
      await expect(
        escrowContract.connect(vendor).refundFunds(tenderId)
      ).to.be.revertedWithCustomError(escrowContract, "AccessControlUnauthorizedAccount");
    });

    it("Should revert if tender is completed", async function () {
      await tenderContract.connect(government).markTenderComplete(tenderId);

      await expect(
        escrowContract.connect(government).refundFunds(tenderId)
      ).to.be.revertedWithCustomError(escrowContract, "TenderNotActive");
    });

    it("Should revert if escrow doesn't exist", async function () {
      await expect(
        escrowContract.connect(government).refundFunds(999)
      ).to.be.revertedWithCustomError(escrowContract, "EscrowNotFound");
    });

    it("Should revert if funds already released", async function () {
      await tenderContract.connect(government).markTenderComplete(tenderId);
      await escrowContract.connect(government).releaseFunds(tenderId, vendor.address);

      await expect(
        escrowContract.connect(government).refundFunds(tenderId)
      ).to.be.revertedWithCustomError(escrowContract, "EscrowAlreadyReleased");
    });
  });

  describe("Escrow Queries", function () {
    let tenderId: number;
    let budget: bigint;

    beforeEach(async function () {
      // Create a tender
      const description = "Road construction project";
      budget = ethers.parseEther("1000000");
      const requirementsCid = "QmTestRequirementsCID";
      const serviceFee = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description, budget, requirementsCid, {
        value: serviceFee
      });

      tenderId = 1;
    });

    it("Should return correct escrow status string", async function () {
      expect(await escrowContract.getEscrowStatusString(tenderId)).to.equal("No Escrow");
      
      await escrowContract.connect(government).depositFunds(tenderId, {
        value: budget
      });
      expect(await escrowContract.getEscrowStatusString(tenderId)).to.equal("Deposited");
      
      await tenderContract.connect(government).markTenderComplete(tenderId);
      await escrowContract.connect(government).releaseFunds(tenderId, vendor.address);
      expect(await escrowContract.getEscrowStatusString(tenderId)).to.equal("Released");
    });

    it("Should return correct escrow existence check", async function () {
      expect(await escrowContract.escrowExists(tenderId)).to.be.false;
      
      await escrowContract.connect(government).depositFunds(tenderId, {
        value: budget
      });
      expect(await escrowContract.escrowExists(tenderId)).to.be.true;
    });

    it("Should return correct escrow release status", async function () {
      expect(await escrowContract.isEscrowReleased(tenderId)).to.be.false;
      
      await escrowContract.connect(government).depositFunds(tenderId, {
        value: budget
      });
      expect(await escrowContract.isEscrowReleased(tenderId)).to.be.false;
      
      await tenderContract.connect(government).markTenderComplete(tenderId);
      await escrowContract.connect(government).releaseFunds(tenderId, vendor.address);
      expect(await escrowContract.isEscrowReleased(tenderId)).to.be.true;
    });

    it("Should return correct total escrow balance", async function () {
      expect(await escrowContract.getTotalEscrowBalance()).to.equal(0);
      
      await escrowContract.connect(government).depositFunds(tenderId, {
        value: budget
      });
      expect(await escrowContract.getTotalEscrowBalance()).to.equal(budget);
      
      await tenderContract.connect(government).markTenderComplete(tenderId);
      await escrowContract.connect(government).releaseFunds(tenderId, vendor.address);
      expect(await escrowContract.getTotalEscrowBalance()).to.equal(0);
    });

    it("Should return correct multiple escrow balances", async function () {
      // Create second tender
      const description2 = "Bridge construction project";
      const budget2 = ethers.parseEther("2000000");
      const requirementsCid2 = "QmTestRequirementsCID2";
      const serviceFee2 = ethers.parseEther("0.01");

      await tenderContract.connect(government).createTender(description2, budget2, requirementsCid2, {
        value: serviceFee2
      });

      const tenderId2 = 2;

      // Deposit funds for both tenders
      await escrowContract.connect(government).depositFunds(tenderId, {
        value: budget
      });
      await escrowContract.connect(government).depositFunds(tenderId2, {
        value: budget2
      });

      const [amounts, depositors, released] = await escrowContract.getMultipleEscrowBalances([tenderId, tenderId2]);
      
      expect(amounts).to.deep.equal([budget, budget2]);
      expect(depositors).to.deep.equal([government.address, government.address]);
      expect(released).to.deep.equal([false, false]);
    });
  });

  describe("Admin Functions", function () {
    it("Should allow admin to update tender contract", async function () {
      await expect(escrowContract.connect(owner).updateTenderContract(addr1.address))
        .to.emit(escrowContract, "TenderContractUpdated")
        .withArgs(addr1.address);

      expect(await escrowContract.tenderContract()).to.equal(addr1.address);
    });

    it("Should allow admin to emergency withdraw", async function () {
      // Send some ETH to contract
      await government.sendTransaction({
        to: escrowContract.target,
        value: ethers.parseEther("1")
      });

      const initialBalance = await ethers.provider.getBalance(addr1.address);
      const withdrawAmount = ethers.parseEther("0.5");

      await escrowContract.connect(owner).emergencyWithdraw(withdrawAmount, addr1.address);

      const finalBalance = await ethers.provider.getBalance(addr1.address);
      expect(finalBalance - initialBalance).to.equal(withdrawAmount);
    });

    it("Should revert emergency withdraw if not admin", async function () {
      await expect(
        escrowContract.connect(vendor).emergencyWithdraw(ethers.parseEther("1"), addr1.address)
      ).to.be.revertedWithCustomError(escrowContract, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Pausable", function () {
    it("Should allow pauser to pause and unpause", async function () {
      await escrowContract.connect(pauser).pause();
      expect(await escrowContract.paused()).to.be.true;

      await escrowContract.connect(pauser).unpause();
      expect(await escrowContract.paused()).to.be.false;
    });

    it("Should not allow non-pauser to pause", async function () {
      await expect(
        escrowContract.connect(vendor).pause()
      ).to.be.revertedWithCustomError(escrowContract, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Security", function () {
    it("Should revert direct ETH transfers", async function () {
      await expect(
        government.sendTransaction({
          to: escrowContract.target,
          value: ethers.parseEther("1")
        })
      ).to.be.revertedWith("Direct deposits not allowed");
    });

    it("Should revert fallback calls", async function () {
      await expect(
        government.sendTransaction({
          to: escrowContract.target,
          data: "0x12345678"
        })
      ).to.be.revertedWith("Function not found");
    });
  });
});
