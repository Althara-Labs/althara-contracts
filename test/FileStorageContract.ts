import { expect } from "chai";
import { FileStorageContract } from "../types/ethers-contracts/index.js";

describe("FileStorageContract", function () {
  let fileStorageContract: FileStorageContract;
  let owner: any;
  let government: any;
  let pauser: any;
  let storageUser: any;
  let addr1: any;

  beforeEach(async function () {
    [owner, government, pauser, storageUser, addr1] = await ethers.getSigners();

    // Deploy FileStorageContract
    const FileStorageContract = await ethers.getContractFactory("FileStorageContract");
    fileStorageContract = await FileStorageContract.deploy(
      owner.address,
      government.address,
      pauser.address
    );

    // Grant STORAGE_ROLE to storageUser for testing
    await fileStorageContract.grantStorageRole(storageUser.address);
  });

  describe("Deployment", function () {
    it("Should set the correct roles", async function () {
      expect(await fileStorageContract.hasRole(await fileStorageContract.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
      expect(await fileStorageContract.hasRole(await fileStorageContract.GOVERNMENT_ROLE(), government.address)).to.be.true;
      expect(await fileStorageContract.hasRole(await fileStorageContract.PAUSER_ROLE(), pauser.address)).to.be.true;
      expect(await fileStorageContract.hasRole(await fileStorageContract.STORAGE_ROLE(), owner.address)).to.be.true;
      expect(await fileStorageContract.hasRole(await fileStorageContract.STORAGE_ROLE(), storageUser.address)).to.be.true;
    });

    it("Should initialize valid entity types", async function () {
      expect(await fileStorageContract.validEntityTypes("tender")).to.be.true;
      expect(await fileStorageContract.validEntityTypes("bid")).to.be.true;
      expect(await fileStorageContract.validEntityTypes("proposal")).to.be.true;
      expect(await fileStorageContract.validEntityTypes("requirements")).to.be.true;
      expect(await fileStorageContract.validEntityTypes("specifications")).to.be.true;
    });

    it("Should have zero initial counts", async function () {
      expect(await fileStorageContract.entityTypeCounts("tender")).to.equal(0);
      expect(await fileStorageContract.entityTypeCounts("bid")).to.equal(0);
    });
  });

  describe("CID Storage", function () {
    it("Should allow storage role to store CID", async function () {
      const entityType = "tender";
      const entityId = 1;
      const cid = "QmTestCID123";

      await expect(
        fileStorageContract.connect(storageUser).storeCid(entityType, entityId, cid)
      )
        .to.emit(fileStorageContract, "CidStored")
        .withArgs(entityType, entityId, cid);

      expect(await fileStorageContract.cids(entityType, entityId)).to.equal(cid);
      expect(await fileStorageContract.entityTypeCounts(entityType)).to.equal(1);
    });

    it("Should revert if non-storage role tries to store CID", async function () {
      const entityType = "tender";
      const entityId = 1;
      const cid = "QmTestCID123";

      await expect(
        fileStorageContract.connect(addr1).storeCid(entityType, entityId, cid)
      ).to.be.revertedWithCustomError(fileStorageContract, "AccessControlUnauthorizedAccount");
    });

    it("Should revert for invalid entity type", async function () {
      const entityType = "invalid";
      const entityId = 1;
      const cid = "QmTestCID123";

      await expect(
        fileStorageContract.connect(storageUser).storeCid(entityType, entityId, cid)
      ).to.be.revertedWithCustomError(fileStorageContract, "InvalidEntityType");
    });

    it("Should revert for empty CID", async function () {
      const entityType = "tender";
      const entityId = 1;
      const cid = "";

      await expect(
        fileStorageContract.connect(storageUser).storeCid(entityType, entityId, cid)
      ).to.be.revertedWithCustomError(fileStorageContract, "InvalidCid");
    });

    it("Should revert if CID already exists", async function () {
      const entityType = "tender";
      const entityId = 1;
      const cid = "QmTestCID123";

      await fileStorageContract.connect(storageUser).storeCid(entityType, entityId, cid);

      await expect(
        fileStorageContract.connect(storageUser).storeCid(entityType, entityId, cid)
      ).to.be.revertedWithCustomError(fileStorageContract, "CidAlreadyExists");
    });
  });

  describe("CID Retrieval", function () {
    beforeEach(async function () {
      // Store some test CIDs
      await fileStorageContract.connect(storageUser).storeCid("tender", 1, "QmTenderCID1");
      await fileStorageContract.connect(storageUser).storeCid("tender", 2, "QmTenderCID2");
      await fileStorageContract.connect(storageUser).storeCid("bid", 1, "QmBidCID1");
    });

    it("Should retrieve CID correctly", async function () {
      const cid = await fileStorageContract.getCid("tender", 1);
      expect(cid).to.equal("QmTenderCID1");
    });

    it("Should revert for non-existent CID", async function () {
      await expect(
        fileStorageContract.getCid("tender", 999)
      ).to.be.revertedWithCustomError(fileStorageContract, "CidNotFound");
    });

    it("Should revert for invalid entity type", async function () {
      await expect(
        fileStorageContract.getCid("invalid", 1)
      ).to.be.revertedWithCustomError(fileStorageContract, "InvalidEntityType");
    });

    it("Should check CID existence correctly", async function () {
      expect(await fileStorageContract.cidExists("tender", 1)).to.be.true;
      expect(await fileStorageContract.cidExists("tender", 999)).to.be.false;
    });
  });

  describe("CID Updates", function () {
    beforeEach(async function () {
      await fileStorageContract.connect(storageUser).storeCid("tender", 1, "QmOldCID");
    });

    it("Should update existing CID", async function () {
      const newCid = "QmNewCID";

      await expect(
        fileStorageContract.connect(storageUser).updateCid("tender", 1, newCid)
      )
        .to.emit(fileStorageContract, "CidUpdated")
        .withArgs("tender", 1, "QmOldCID", newCid);

      expect(await fileStorageContract.getCid("tender", 1)).to.equal(newCid);
    });

    it("Should revert when updating non-existent CID", async function () {
      await expect(
        fileStorageContract.connect(storageUser).updateCid("tender", 999, "QmNewCID")
      ).to.be.revertedWithCustomError(fileStorageContract, "CidNotFound");
    });
  });

  describe("CID Removal", function () {
    beforeEach(async function () {
      await fileStorageContract.connect(storageUser).storeCid("tender", 1, "QmTestCID");
    });

    it("Should remove existing CID", async function () {
      await expect(
        fileStorageContract.connect(storageUser).removeCid("tender", 1)
      )
        .to.emit(fileStorageContract, "CidRemoved")
        .withArgs("tender", 1, "QmTestCID");

      expect(await fileStorageContract.cidExists("tender", 1)).to.be.false;
      expect(await fileStorageContract.entityTypeCounts("tender")).to.equal(0);
    });

    it("Should revert when removing non-existent CID", async function () {
      await expect(
        fileStorageContract.connect(storageUser).removeCid("tender", 999)
      ).to.be.revertedWithCustomError(fileStorageContract, "CidNotFound");
    });
  });

  describe("Multiple CID Operations", function () {
    beforeEach(async function () {
      // Store multiple CIDs
      await fileStorageContract.connect(storageUser).storeCid("tender", 1, "QmTender1");
      await fileStorageContract.connect(storageUser).storeCid("tender", 2, "QmTender2");
      await fileStorageContract.connect(storageUser).storeCid("tender", 5, "QmTender5");
      await fileStorageContract.connect(storageUser).storeCid("bid", 1, "QmBid1");
    });

    it("Should get multiple CIDs in range", async function () {
      const [entityIds, cidArray] = await fileStorageContract.getMultipleCids("tender", 1, 5);
      
      expect(entityIds).to.deep.equal([1n, 2n, 5n]);
      expect(cidArray).to.deep.equal(["QmTender1", "QmTender2", "QmTender5"]);
    });

    it("Should get all CIDs for entity type", async function () {
      const [entityIds, cidArray] = await fileStorageContract.getAllCidsForType("tender");
      
      expect(entityIds).to.deep.equal([1n, 2n, 5n]);
      expect(cidArray).to.deep.equal(["QmTender1", "QmTender2", "QmTender5"]);
    });

    it("Should return empty arrays for entity type with no CIDs", async function () {
      const [entityIds, cidArray] = await fileStorageContract.getAllCidsForType("proposal");
      
      expect(entityIds).to.deep.equal([]);
      expect(cidArray).to.deep.equal([]);
    });
  });

  describe("Entity Type Management", function () {
    it("Should allow admin to add new entity type", async function () {
      await expect(
        fileStorageContract.connect(owner).addEntityType("contract")
      )
        .to.emit(fileStorageContract, "EntityTypeAdded")
        .withArgs("contract");

      expect(await fileStorageContract.validEntityTypes("contract")).to.be.true;
    });

    it("Should allow admin to remove entity type", async function () {
      // First add a new entity type
      await fileStorageContract.connect(owner).addEntityType("contract");

      await expect(
        fileStorageContract.connect(owner).removeEntityType("contract")
      )
        .to.emit(fileStorageContract, "EntityTypeRemoved")
        .withArgs("contract");

      expect(await fileStorageContract.validEntityTypes("contract")).to.be.false;
    });

    it("Should not allow removal of core entity types", async function () {
      await expect(
        fileStorageContract.connect(owner).removeEntityType("tender")
      ).to.be.revertedWith("Cannot remove core entity types");

      await expect(
        fileStorageContract.connect(owner).removeEntityType("bid")
      ).to.be.revertedWith("Cannot remove core entity types");
    });

    it("Should revert if non-admin tries to add entity type", async function () {
      await expect(
        fileStorageContract.connect(storageUser).addEntityType("contract")
      ).to.be.revertedWithCustomError(fileStorageContract, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Role Management", function () {
    it("Should allow admin to grant storage role", async function () {
      await fileStorageContract.connect(owner).grantStorageRole(addr1.address);
      expect(await fileStorageContract.hasRole(await fileStorageContract.STORAGE_ROLE(), addr1.address)).to.be.true;
    });

    it("Should allow admin to revoke storage role", async function () {
      await fileStorageContract.connect(owner).revokeStorageRole(storageUser.address);
      expect(await fileStorageContract.hasRole(await fileStorageContract.STORAGE_ROLE(), storageUser.address)).to.be.false;
    });

    it("Should revert if non-admin tries to grant role", async function () {
      await expect(
        fileStorageContract.connect(storageUser).grantStorageRole(addr1.address)
      ).to.be.revertedWithCustomError(fileStorageContract, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Contract Statistics", function () {
    beforeEach(async function () {
      // Store some CIDs
      await fileStorageContract.connect(storageUser).storeCid("tender", 1, "QmTender1");
      await fileStorageContract.connect(storageUser).storeCid("tender", 2, "QmTender2");
      await fileStorageContract.connect(storageUser).storeCid("bid", 1, "QmBid1");
    });

    it("Should return correct statistics", async function () {
      const [totalEntityTypes, totalCids] = await fileStorageContract.getContractStats();
      
      expect(totalEntityTypes).to.equal(5); // tender, bid, proposal, requirements, specifications
      expect(totalCids).to.equal(3); // 2 tenders + 1 bid
    });
  });

  describe("Pausable", function () {
    it("Should allow pauser to pause and unpause", async function () {
      await fileStorageContract.connect(pauser).pause();
      expect(await fileStorageContract.paused()).to.be.true;

      await fileStorageContract.connect(pauser).unpause();
      expect(await fileStorageContract.paused()).to.be.false;
    });

    it("Should not allow non-pauser to pause", async function () {
      await expect(
        fileStorageContract.connect(storageUser).pause()
      ).to.be.revertedWithCustomError(fileStorageContract, "AccessControlUnauthorizedAccount");
    });

    it("Should prevent operations when paused", async function () {
      await fileStorageContract.connect(pauser).pause();

      await expect(
        fileStorageContract.connect(storageUser).storeCid("tender", 1, "QmTestCID")
      ).to.be.revertedWithCustomError(fileStorageContract, "EnforcedPause");
    });
  });
});
