// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {FileStorageContract} from "../contracts/FileStorageContract.sol";

contract FileStorageContractTest is Test {
    FileStorageContract public fileStorageContract;
    
    address public owner;
    address public government;
    address public pauser;
    address public user1;
    address public user2;

    function setUp() public {
        owner = makeAddr("owner");
        government = makeAddr("government");
        pauser = makeAddr("pauser");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);

        fileStorageContract = new FileStorageContract(
            owner,
            government,
            pauser
        );

        vm.stopPrank();
    }

    // Deployment tests
    function test_ShouldSetCorrectRoles() public {
        assertTrue(fileStorageContract.hasRole(fileStorageContract.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(fileStorageContract.hasRole(fileStorageContract.GOVERNMENT_ROLE(), government));
        assertTrue(fileStorageContract.hasRole(fileStorageContract.PAUSER_ROLE(), pauser));
        assertTrue(fileStorageContract.hasRole(fileStorageContract.STORAGE_ROLE(), owner));
    }

    function test_ShouldSetCorrectValidEntityTypes() public {
        assertTrue(fileStorageContract.validEntityTypes("tender"));
        assertTrue(fileStorageContract.validEntityTypes("bid"));
        assertTrue(fileStorageContract.validEntityTypes("proposal"));
        assertTrue(fileStorageContract.validEntityTypes("requirements"));
        assertTrue(fileStorageContract.validEntityTypes("specifications"));
        assertFalse(fileStorageContract.validEntityTypes("invalid"));
    }

    // CID Storage tests
    function test_ShouldAllowStorageRoleToStoreCid() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory cid = "QmTestCID123";

        vm.startPrank(owner);
        
        vm.expectEmit(true, true, false, false);
        emit FileStorageContract.CidStored(entityType, entityId, cid);
        
        fileStorageContract.storeCid(entityType, entityId, cid);

        vm.stopPrank();

        assertEq(fileStorageContract.cids(entityType, entityId), cid);
        assertEq(fileStorageContract.entityTypeCounts(entityType), 1);
    }

    function test_ShouldRevertIfNonStorageRoleTriesToStoreCid() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory cid = "QmTestCID123";

        vm.startPrank(user1);
        
        vm.expectRevert();
        
        fileStorageContract.storeCid(entityType, entityId, cid);

        vm.stopPrank();
    }

    function test_ShouldRevertIfInvalidEntityType() public {
        string memory entityType = "invalid";
        uint256 entityId = 1;
        string memory cid = "QmTestCID123";

        vm.startPrank(owner);
        
        vm.expectRevert(abi.encodeWithSelector(FileStorageContract.InvalidEntityType.selector));
        
        fileStorageContract.storeCid(entityType, entityId, cid);

        vm.stopPrank();
    }

    function test_ShouldRevertIfEmptyCid() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory cid = "";

        vm.startPrank(owner);
        
        vm.expectRevert(abi.encodeWithSelector(FileStorageContract.InvalidCid.selector));
        
        fileStorageContract.storeCid(entityType, entityId, cid);

        vm.stopPrank();
    }

    function test_ShouldRevertIfCidAlreadyExists() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory cid = "QmTestCID123";

        vm.startPrank(owner);
        fileStorageContract.storeCid(entityType, entityId, cid);
        
        vm.expectRevert(abi.encodeWithSelector(FileStorageContract.CidAlreadyExists.selector));
        fileStorageContract.storeCid(entityType, entityId, "QmAnotherCID");
        vm.stopPrank();
    }

    // CID Management tests
    function test_ShouldAllowStorageRoleToUpdateCid() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory oldCid = "QmTestCID123";
        string memory newCid = "QmUpdatedCID456";

        vm.startPrank(owner);
        fileStorageContract.storeCid(entityType, entityId, oldCid);
        
        vm.expectEmit(true, true, false, false);
        emit FileStorageContract.CidUpdated(entityType, entityId, oldCid, newCid);
        
        fileStorageContract.updateCid(entityType, entityId, newCid);

        vm.stopPrank();

        assertEq(fileStorageContract.cids(entityType, entityId), newCid);
    }

    function test_ShouldRevertIfNonStorageRoleTriesToUpdateCid() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory cid = "QmTestCID123";
        string memory newCid = "QmUpdatedCID456";

        vm.startPrank(owner);
        fileStorageContract.storeCid(entityType, entityId, cid);
        vm.stopPrank();

        vm.startPrank(user1);
        
        vm.expectRevert();
        
        fileStorageContract.updateCid(entityType, entityId, newCid);

        vm.stopPrank();
    }

    function test_ShouldRevertIfCidNotFoundForUpdate() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory newCid = "QmUpdatedCID456";

        vm.startPrank(owner);
        
        vm.expectRevert(abi.encodeWithSelector(FileStorageContract.CidNotFound.selector));
        
        fileStorageContract.updateCid(entityType, entityId, newCid);

        vm.stopPrank();
    }

    function test_ShouldAllowStorageRoleToRemoveCid() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory cid = "QmTestCID123";

        vm.startPrank(owner);
        fileStorageContract.storeCid(entityType, entityId, cid);
        
        vm.expectEmit(true, true, false, false);
        emit FileStorageContract.CidRemoved(entityType, entityId, cid);
        
        fileStorageContract.removeCid(entityType, entityId);

        vm.stopPrank();

        assertEq(fileStorageContract.cids(entityType, entityId), "");
        assertEq(fileStorageContract.entityTypeCounts(entityType), 0);
    }

    function test_ShouldRevertIfNonStorageRoleTriesToRemoveCid() public {
        string memory entityType = "tender";
        uint256 entityId = 1;
        string memory cid = "QmTestCID123";

        vm.startPrank(owner);
        fileStorageContract.storeCid(entityType, entityId, cid);
        vm.stopPrank();

        vm.startPrank(user1);
        
        vm.expectRevert();
        
        fileStorageContract.removeCid(entityType, entityId);

        vm.stopPrank();
    }

    function test_ShouldRevertIfCidNotFoundForRemoval() public {
        string memory entityType = "tender";
        uint256 entityId = 1;

        vm.startPrank(owner);
        
        vm.expectRevert(abi.encodeWithSelector(FileStorageContract.CidNotFound.selector));
        
        fileStorageContract.removeCid(entityType, entityId);

        vm.stopPrank();
    }

    // Entity Type Management tests
    function test_ShouldAllowAdminToAddEntityType() public {
        string memory newEntityType = "contract";

        vm.startPrank(owner);
        
        vm.expectEmit(false, false, false, false);
        emit FileStorageContract.EntityTypeAdded(newEntityType);
        
        fileStorageContract.addEntityType(newEntityType);

        vm.stopPrank();

        assertTrue(fileStorageContract.validEntityTypes(newEntityType));
    }

    function test_ShouldAllowAdminToRemoveEntityType() public {
        string memory entityType = "tender";

        vm.startPrank(owner);
        
        vm.expectEmit(false, false, false, false);
        emit FileStorageContract.EntityTypeRemoved(entityType);
        
        fileStorageContract.removeEntityType(entityType);

        vm.stopPrank();

        assertFalse(fileStorageContract.validEntityTypes(entityType));
    }

    function test_ShouldRevertIfNonAdminTriesToAddEntityType() public {
        string memory newEntityType = "contract";

        vm.startPrank(user1);
        
        vm.expectRevert();
        
        fileStorageContract.addEntityType(newEntityType);

        vm.stopPrank();
    }

    function test_ShouldRevertIfNonAdminTriesToRemoveEntityType() public {
        string memory entityType = "tender";

        vm.startPrank(user1);
        
        vm.expectRevert();
        
        fileStorageContract.removeEntityType(entityType);

        vm.stopPrank();
    }

    // Pausable tests
    function test_ShouldAllowPauserToPauseAndUnpause() public {
        vm.startPrank(pauser);
        
        fileStorageContract.pause();
        assertTrue(fileStorageContract.paused());

        fileStorageContract.unpause();
        assertFalse(fileStorageContract.paused());
        
        vm.stopPrank();
    }

    function test_ShouldNotAllowNonPauserToPause() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        fileStorageContract.pause();
        
        vm.stopPrank();
    }

    function test_ShouldRevertIfContractIsPaused() public {
        vm.startPrank(pauser);
        fileStorageContract.pause();
        vm.stopPrank();

        vm.startPrank(owner);
        
        vm.expectRevert();
        fileStorageContract.storeCid("tender", 1, "QmTestCID123");
        
        vm.stopPrank();
    }
}
