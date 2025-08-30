// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {TenderContract} from "../contracts/TenderContract.sol";

contract TenderContractTest is Test {
    TenderContract public tenderContract;
    
    address public owner;
    address public government;
    address public pauser;
    address public platformWallet;
    address public bidder;
    address public addr1;

    function setUp() public {
        owner = makeAddr("owner");
        government = makeAddr("government");
        pauser = makeAddr("pauser");
        platformWallet = makeAddr("platformWallet");
        bidder = makeAddr("bidder");
        addr1 = makeAddr("addr1");

        vm.startPrank(owner);

        tenderContract = new TenderContract(
            owner,
            government,
            pauser,
            platformWallet
        );

        vm.stopPrank();
    }

    // Deployment tests
    function test_ShouldSetCorrectRoles() public {
        assertTrue(tenderContract.hasRole(tenderContract.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(tenderContract.hasRole(tenderContract.GOVERNMENT_ROLE(), government));
        assertTrue(tenderContract.hasRole(tenderContract.PAUSER_ROLE(), pauser));
    }

    function test_ShouldSetCorrectPlatformWallet() public {
        assertEq(tenderContract.platformWallet(), platformWallet);
    }

    function test_ShouldSetCorrectServiceFee() public {
        assertEq(tenderContract.serviceFee(), 0.01 ether);
    }

    // Tender Creation tests
    function test_ShouldAllowGovernmentToCreateTender() public {
        string memory description = "Road construction project";
        uint256 budget = 1000000 ether;
        string memory requirementsCid = "QmTestRequirementsCID";
        uint256 serviceFee = 0.01 ether;

        uint256 initialBalance = platformWallet.balance;

        vm.startPrank(government);
        
        vm.expectEmit(true, true, true, true);
        emit TenderContract.TenderCreated(1, government, description, budget);
        
        tenderContract.createTender{value: serviceFee}(description, budget, requirementsCid);

        vm.stopPrank();

        (string memory tenderDesc, uint256 tenderBudget, string memory tenderCid, bool completed, uint256[] memory bidIds) = 
            tenderContract.getTenderDetails(1);
        
        assertEq(tenderDesc, description);
        assertEq(tenderBudget, budget);
        assertEq(tenderCid, requirementsCid);
        assertEq(completed, false);
        assertEq(bidIds.length, 0);

        assertEq(platformWallet.balance - initialBalance, serviceFee);
    }

    function test_ShouldRevertIfNonGovernmentTriesToCreateTender() public {
        string memory description = "Road construction project";
        uint256 budget = 1000000 ether;
        string memory requirementsCid = "QmTestRequirementsCID";
        uint256 serviceFee = 0.01 ether;

        vm.startPrank(bidder);
        
        vm.expectRevert();
        
        tenderContract.createTender{value: serviceFee}(description, budget, requirementsCid);

        vm.stopPrank();
    }

    function test_ShouldRevertIfInsufficientServiceFee() public {
        string memory description = "Road construction project";
        uint256 budget = 1000000 ether;
        string memory requirementsCid = "QmTestRequirementsCID";
        uint256 insufficientFee = 0.005 ether;

        vm.startPrank(government);
        
        vm.expectRevert(abi.encodeWithSelector(TenderContract.InsufficientServiceFee.selector));
        
        tenderContract.createTender{value: insufficientFee}(description, budget, requirementsCid);

        vm.stopPrank();
    }

    // Tender Management tests
    function test_ShouldAllowGovernmentToMarkTenderComplete() public {
        uint256 tenderId = _createTender();

        vm.startPrank(government);
        
        vm.expectEmit(true, true, false, false);
        emit TenderContract.TenderCompleted(tenderId);
        
        tenderContract.markTenderComplete(tenderId);

        vm.stopPrank();

(,,, bool completed,) = tenderContract.getTenderDetails(tenderId);
        assertEq(completed, true);
    }

    function test_ShouldRevertIfNonGovernmentTriesToMarkTenderComplete() public {
        uint256 tenderId = _createTender();

        vm.startPrank(bidder);
        
        vm.expectRevert();
        
        tenderContract.markTenderComplete(tenderId);

        vm.stopPrank();
    }

    function test_ShouldRevertIfTenderAlreadyCompleted() public {
        uint256 tenderId = _createTender();

        vm.startPrank(government);
        tenderContract.markTenderComplete(tenderId);
        
        vm.expectRevert(abi.encodeWithSelector(TenderContract.TenderAlreadyCompleted.selector));
        tenderContract.markTenderComplete(tenderId);
        vm.stopPrank();
    }

    function test_ShouldRevertForInvalidTenderId() public {
        vm.startPrank(government);
        
        vm.expectRevert(abi.encodeWithSelector(TenderContract.TenderNotFound.selector));
        tenderContract.markTenderComplete(999);
        
        vm.stopPrank();
    }

    // Tender Queries tests
    function test_ShouldReturnCorrectTenderCount() public {
        _createTender();
        _createTender();

        assertEq(tenderContract.getTenderCount(), 2);
    }

    function test_ShouldReturnCorrectTenderDetails() public {
        uint256 tenderId = _createTender();

        (string memory tenderDesc, uint256 tenderBudget, string memory tenderCid, bool completed, uint256[] memory bidIds) = 
            tenderContract.getTenderDetails(tenderId);
        
        assertEq(tenderDesc, "Road construction project");
        assertEq(tenderBudget, 1000000 ether);
        assertEq(tenderCid, "QmTestRequirementsCID");
        assertEq(completed, false);
        assertEq(bidIds.length, 0);
    }





    // Admin Functions tests
    function test_ShouldAllowAdminToUpdateServiceFee() public {
        uint256 newFee = 0.02 ether;
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit TenderContract.ServiceFeeUpdated(newFee);
        
        tenderContract.updateServiceFee(newFee);

        vm.stopPrank();

        assertEq(tenderContract.serviceFee(), newFee);
    }

    function test_ShouldAllowAdminToUpdatePlatformWallet() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit TenderContract.PlatformWalletUpdated(addr1);
        
        tenderContract.updatePlatformWallet(addr1);

        vm.stopPrank();

        assertEq(tenderContract.platformWallet(), addr1);
    }

    // Pausable tests
    function test_ShouldAllowPauserToPauseAndUnpause() public {
        vm.startPrank(pauser);
        
        tenderContract.pause();
        assertTrue(tenderContract.paused());

        tenderContract.unpause();
        assertFalse(tenderContract.paused());
        
        vm.stopPrank();
    }

    function test_ShouldNotAllowNonPauserToPause() public {
        vm.startPrank(bidder);
        
        vm.expectRevert();
        tenderContract.pause();
        
        vm.stopPrank();
    }

    // Helper functions
    function _createTender() internal returns (uint256) {
        string memory description = "Road construction project";
        uint256 budget = 1000000 ether;
        string memory requirementsCid = "QmTestRequirementsCID";
        uint256 serviceFee = 0.01 ether;

        // Give government some ETH to pay the service fee
        vm.deal(government, 1000 ether);

        vm.startPrank(government);
        tenderContract.createTender{value: serviceFee}(description, budget, requirementsCid);
        vm.stopPrank();

        return 1; // First tender ID
    }
}
