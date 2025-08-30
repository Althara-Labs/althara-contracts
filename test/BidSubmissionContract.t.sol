// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {BidSubmissionContract} from "../contracts/BidSubmissionContract.sol";
import {TenderContract} from "../contracts/TenderContract.sol";

contract BidSubmissionContractTest is Test {
    BidSubmissionContract public bidSubmissionContract;
    TenderContract public tenderContract;
    
    address public owner;
    address public government;
    address public pauser;
    address public platformWallet;
    address public vendor1;
    address public vendor2;
    address public addr1;

    function setUp() public {
        owner = makeAddr("owner");
        government = makeAddr("government");
        pauser = makeAddr("pauser");
        platformWallet = makeAddr("platformWallet");
        vendor1 = makeAddr("vendor1");
        vendor2 = makeAddr("vendor2");
        addr1 = makeAddr("addr1");

        vm.startPrank(owner);

        // Deploy TenderContract first
        tenderContract = new TenderContract(
            owner,
            government,
            pauser,
            platformWallet
        );

        // Deploy BidSubmissionContract
        bidSubmissionContract = new BidSubmissionContract(
            owner,
            government,
            pauser,
            platformWallet,
            address(tenderContract)
        );

        // Grant BID_SUBMISSION_ROLE to BidSubmissionContract
        tenderContract.grantBidSubmissionRole(address(bidSubmissionContract));

        vm.stopPrank();
    }

    // Deployment tests
    function test_ShouldSetCorrectRoles() public {
        assertTrue(bidSubmissionContract.hasRole(bidSubmissionContract.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(bidSubmissionContract.hasRole(bidSubmissionContract.GOVERNMENT_ROLE(), government));
        assertTrue(bidSubmissionContract.hasRole(bidSubmissionContract.PAUSER_ROLE(), pauser));
    }

    function test_ShouldSetCorrectPlatformWallet() public {
        assertEq(bidSubmissionContract.platformWallet(), platformWallet);
    }

    function test_ShouldSetCorrectServiceFee() public {
        assertEq(bidSubmissionContract.serviceFee(), 0.005 ether);
    }

    function test_ShouldSetCorrectTenderContract() public {
        assertEq(address(bidSubmissionContract.tenderContract()), address(tenderContract));
    }

    // Bid Submission tests
    function test_ShouldAllowVendorToSubmitBid() public {
        uint256 tenderId = _createTender();
        
        uint256 price = 800000 ether;
        string memory description = "Our construction proposal";
        string memory proposalCid = "QmProposalCID";
        uint256 bidServiceFee = 0.005 ether;

        uint256 initialBalance = platformWallet.balance;

        vm.startPrank(vendor1);
        
        vm.expectEmit(true, true, true, true);
        emit BidSubmissionContract.BidSubmitted(1, tenderId, vendor1, price);
        
        bidSubmissionContract.submitBid{value: bidServiceFee}(
            tenderId, 
            price, 
            description, 
            proposalCid
        );

        vm.stopPrank();

        (uint256 bidTenderId, address bidVendor, uint256 bidPrice, string memory bidDesc, string memory bidProposalCid, uint8 bidStatus) = 
            bidSubmissionContract.getBidDetails(1);
        
        assertEq(bidTenderId, tenderId);
        assertEq(bidVendor, vendor1);
        assertEq(bidPrice, price);
        assertEq(bidDesc, description);
        assertEq(bidProposalCid, proposalCid);
        assertEq(bidStatus, 0); // Pending

        assertEq(platformWallet.balance - initialBalance, bidServiceFee);
    }

    function test_ShouldRevertIfInsufficientServiceFee() public {
        uint256 tenderId = _createTender();
        
        uint256 price = 800000 ether;
        string memory description = "Our construction proposal";
        string memory proposalCid = "QmProposalCID";
        uint256 insufficientFee = 0.002 ether;

        vm.startPrank(vendor1);
        
        vm.expectRevert(abi.encodeWithSelector(BidSubmissionContract.InsufficientServiceFee.selector));
        
        bidSubmissionContract.submitBid{value: insufficientFee}(
            tenderId, 
            price, 
            description, 
            proposalCid
        );

        vm.stopPrank();
    }

    function test_ShouldRevertIfTenderCompleted() public {
        uint256 tenderId = _createTender();
        
        // Mark tender as completed
        vm.prank(government);
        tenderContract.markTenderComplete(tenderId);

        uint256 price = 800000 ether;
        string memory description = "Our construction proposal";
        string memory proposalCid = "QmProposalCID";
        uint256 bidServiceFee = 0.005 ether;

        vm.startPrank(vendor1);
        
        vm.expectRevert(abi.encodeWithSelector(BidSubmissionContract.TenderNotActive.selector));
        
        bidSubmissionContract.submitBid{value: bidServiceFee}(
            tenderId, 
            price, 
            description, 
            proposalCid
        );

        vm.stopPrank();
    }

    function test_ShouldRevertForInvalidTenderId() public {
        uint256 price = 800000 ether;
        string memory description = "Our construction proposal";
        string memory proposalCid = "QmProposalCID";
        uint256 bidServiceFee = 0.005 ether;

        vm.startPrank(vendor1);
        
        vm.expectRevert(abi.encodeWithSelector(BidSubmissionContract.TenderNotFound.selector));
        
        bidSubmissionContract.submitBid{value: bidServiceFee}(
            999, 
            price, 
            description, 
            proposalCid
        );

        vm.stopPrank();
    }

    // Bid Management tests
    function test_ShouldAllowGovernmentToAcceptBid() public {
        uint256 tenderId = _createTender();
        uint256 bidId = _submitBid(tenderId);

        vm.startPrank(government);
        
        vm.expectEmit(true, true, false, false);
        emit BidSubmissionContract.BidAccepted(bidId, tenderId);
        
        bidSubmissionContract.acceptBid(tenderId, bidId);

        vm.stopPrank();

        (,,,,, uint8 status) = bidSubmissionContract.getBidDetails(bidId);
        assertEq(status, 1); // Accepted
    }

    function test_ShouldAllowGovernmentToRejectBid() public {
        uint256 tenderId = _createTender();
        uint256 bidId = _submitBid(tenderId);

        vm.startPrank(government);
        
        vm.expectEmit(true, true, false, false);
        emit BidSubmissionContract.BidRejected(bidId, tenderId);
        
        bidSubmissionContract.rejectBid(tenderId, bidId);

        vm.stopPrank();

        (,,,,, uint8 status) = bidSubmissionContract.getBidDetails(bidId);
        assertEq(status, 2); // Rejected
    }

    function test_ShouldRevertIfNonGovernmentTriesToAcceptBid() public {
        uint256 tenderId = _createTender();
        uint256 bidId = _submitBid(tenderId);

        vm.startPrank(vendor1);
        
        vm.expectRevert();
        
        bidSubmissionContract.acceptBid(tenderId, bidId);

        vm.stopPrank();
    }

    function test_ShouldRevertIfNonGovernmentTriesToRejectBid() public {
        uint256 tenderId = _createTender();
        uint256 bidId = _submitBid(tenderId);

        vm.startPrank(vendor1);
        
        vm.expectRevert();
        
        bidSubmissionContract.rejectBid(tenderId, bidId);

        vm.stopPrank();
    }

    function test_ShouldRevertIfTryingToAcceptAlreadyProcessedBid() public {
        uint256 tenderId = _createTender();
        uint256 bidId = _submitBid(tenderId);

        vm.startPrank(government);
        bidSubmissionContract.acceptBid(tenderId, bidId);
        
        vm.expectRevert(abi.encodeWithSelector(BidSubmissionContract.BidAlreadyProcessed.selector));
        bidSubmissionContract.acceptBid(tenderId, bidId);
        vm.stopPrank();
    }

    function test_ShouldRevertIfTryingToRejectAlreadyProcessedBid() public {
        uint256 tenderId = _createTender();
        uint256 bidId = _submitBid(tenderId);

        vm.startPrank(government);
        bidSubmissionContract.rejectBid(tenderId, bidId);
        
        vm.expectRevert(abi.encodeWithSelector(BidSubmissionContract.BidAlreadyProcessed.selector));
        bidSubmissionContract.rejectBid(tenderId, bidId);
        vm.stopPrank();
    }

    function test_ShouldRevertForInvalidBidId() public {
        uint256 tenderId = _createTender();

        vm.startPrank(government);
        
        vm.expectRevert(abi.encodeWithSelector(BidSubmissionContract.InvalidBidId.selector));
        bidSubmissionContract.acceptBid(tenderId, 999);
        
        vm.stopPrank();
    }

    function test_ShouldRevertIfBidDoesntBelongToTender() public {
        uint256 tenderId1 = _createTender();
        uint256 tenderId2 = _createTender();
        
        uint256 bidId2 = _submitBid(tenderId2);

        vm.startPrank(government);
        
        vm.expectRevert(abi.encodeWithSelector(BidSubmissionContract.InvalidTenderId.selector));
        bidSubmissionContract.acceptBid(tenderId1, bidId2);
        
        vm.stopPrank();
    }

    // Bid Queries tests
    function test_ShouldReturnCorrectBidCount() public {
        uint256 tenderId = _createTender();
        _submitBid(tenderId);
        _submitBid(tenderId);

        assertEq(bidSubmissionContract.getBidCount(), 2);
    }

    function test_ShouldReturnCorrectBidDetails() public {
        uint256 tenderId = _createTender();
        _submitBid(tenderId);

        (uint256 bidTenderId, address bidVendor, uint256 bidPrice, string memory bidDesc, string memory bidProposalCid, uint8 bidStatus) = 
            bidSubmissionContract.getBidDetails(1);
        
        assertEq(bidTenderId, tenderId);
        assertEq(bidVendor, vendor1);
        assertEq(bidPrice, 800000 ether);
        assertEq(bidDesc, "Vendor 1 proposal");
        assertEq(bidProposalCid, "QmProposal1");
        assertEq(bidStatus, 0); // Pending
    }

    function test_ShouldReturnCorrectBidInfoWithTimestamp() public {
        uint256 tenderId = _createTender();
        _submitBid(tenderId);

        (uint256 bidTenderId, address bidVendor, uint256 bidPrice, string memory bidDesc, string memory bidProposalCid, uint8 bidStatus, uint256 submittedAt) = 
            bidSubmissionContract.getBidInfo(1);
        
        assertEq(bidTenderId, tenderId);
        assertEq(bidVendor, vendor1);
        assertEq(bidPrice, 800000 ether);
        assertEq(bidDesc, "Vendor 1 proposal");
        assertEq(bidProposalCid, "QmProposal1");
        assertEq(bidStatus, 0); // Pending
        assertGt(submittedAt, 0);
    }

    function test_ShouldReturnCorrectTenderBids() public {
        uint256 tenderId = _createTender();
        _submitBid(tenderId);
        _submitBid(tenderId);

        uint256[] memory tenderBids = bidSubmissionContract.getTenderBids(tenderId);
        assertEq(tenderBids.length, 2);
        assertEq(tenderBids[0], 1);
        assertEq(tenderBids[1], 2);
    }

    function test_ShouldReturnCorrectVendorBids() public {
        uint256 tenderId = _createTender();
        _submitBid(tenderId);
        
        // Submit bid from vendor2
        vm.startPrank(vendor2);
        bidSubmissionContract.submitBid{value: 0.005 ether}(
            tenderId, 
            750000 ether, 
            "Vendor 2 proposal", 
            "QmProposal2"
        );
        vm.stopPrank();

        uint256[] memory vendor1Bids = bidSubmissionContract.getVendorBids(vendor1);
        assertEq(vendor1Bids.length, 1);
        assertEq(vendor1Bids[0], 1);

        uint256[] memory vendor2Bids = bidSubmissionContract.getVendorBids(vendor2);
        assertEq(vendor2Bids.length, 1);
        assertEq(vendor2Bids[0], 2);
    }

    function test_ShouldReturnCorrectBidStatusString() public {
        uint256 tenderId = _createTender();
        _submitBid(tenderId);
        
        assertEq(bidSubmissionContract.getBidStatusString(1), "Pending");
        
        vm.prank(government);
        bidSubmissionContract.acceptBid(tenderId, 1);
        assertEq(bidSubmissionContract.getBidStatusString(1), "Accepted");
        
        vm.prank(government);
        bidSubmissionContract.rejectBid(tenderId, 2);
        assertEq(bidSubmissionContract.getBidStatusString(2), "Rejected");
    }

    function test_ShouldReturnCorrectBidExistenceCheck() public {
        uint256 tenderId = _createTender();
        _submitBid(tenderId);
        _submitBid(tenderId);

        assertTrue(bidSubmissionContract.bidExists(1));
        assertTrue(bidSubmissionContract.bidExists(2));
        assertFalse(bidSubmissionContract.bidExists(999));
    }

    // Admin Functions tests
    function test_ShouldAllowAdminToUpdateServiceFee() public {
        uint256 newFee = 0.01 ether;
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit BidSubmissionContract.ServiceFeeUpdated(newFee);
        
        bidSubmissionContract.updateServiceFee(newFee);

        vm.stopPrank();

        assertEq(bidSubmissionContract.serviceFee(), newFee);
    }

    function test_ShouldAllowAdminToUpdatePlatformWallet() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit BidSubmissionContract.PlatformWalletUpdated(addr1);
        
        bidSubmissionContract.updatePlatformWallet(addr1);

        vm.stopPrank();

        assertEq(bidSubmissionContract.platformWallet(), addr1);
    }

    function test_ShouldAllowAdminToUpdateTenderContract() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit BidSubmissionContract.TenderContractUpdated(addr1);
        
        bidSubmissionContract.updateTenderContract(addr1);

        vm.stopPrank();

        assertEq(address(bidSubmissionContract.tenderContract()), addr1);
    }

    // Pausable tests
    function test_ShouldAllowPauserToPauseAndUnpause() public {
        vm.startPrank(pauser);
        
        bidSubmissionContract.pause();
        assertTrue(bidSubmissionContract.paused());

        bidSubmissionContract.unpause();
        assertFalse(bidSubmissionContract.paused());
        
        vm.stopPrank();
    }

    function test_ShouldNotAllowNonPauserToPause() public {
        vm.startPrank(vendor1);
        
        vm.expectRevert();
        bidSubmissionContract.pause();
        
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

    function _submitBid(uint256 tenderId) internal returns (uint256) {
        uint256 price = 800000 ether;
        string memory description = "Vendor 1 proposal";
        string memory proposalCid = "QmProposal1";
        uint256 bidServiceFee = 0.005 ether;

        // Give vendor1 some ETH to pay the service fee
        vm.deal(vendor1, 1000 ether);

        vm.startPrank(vendor1);
        bidSubmissionContract.submitBid{value: bidServiceFee}(
            tenderId, 
            price, 
            description, 
            proposalCid
        );
        vm.stopPrank();

        return 1; // First bid ID
    }
}
