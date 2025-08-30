// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {EscrowContract} from "../contracts/EscrowContract.sol";
import {TenderContract} from "../contracts/TenderContract.sol";

contract EscrowContractTest is Test {
    EscrowContract public escrowContract;
    TenderContract public tenderContract;
    
    address public owner;
    address public government;
    address public pauser;
    address public vendor1;
    address public vendor2;

    function setUp() public {
        owner = makeAddr("owner");
        government = makeAddr("government");
        pauser = makeAddr("pauser");
        vendor1 = makeAddr("vendor1");
        vendor2 = makeAddr("vendor2");

        vm.startPrank(owner);

        // Deploy TenderContract first
        tenderContract = new TenderContract(
            owner,
            government,
            pauser,
            owner // platform wallet
        );

        // Deploy EscrowContract
        escrowContract = new EscrowContract(
            owner,
            government,
            pauser,
            address(tenderContract)
        );

        vm.stopPrank();
    }

    // Deployment tests
    function test_ShouldSetCorrectRoles() public {
        assertTrue(escrowContract.hasRole(escrowContract.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(escrowContract.hasRole(escrowContract.GOVERNMENT_ROLE(), government));
        assertTrue(escrowContract.hasRole(escrowContract.PAUSER_ROLE(), pauser));
    }

    // Escrow Creation tests
    function test_ShouldAllowGovernmentToDepositFunds() public {
        uint256 tenderId = _createTender();
        uint256 tenderBudget = 1000000 ether;

        vm.startPrank(government);
        
        vm.expectEmit(true, true, true, false);
        emit EscrowContract.FundsDeposited(tenderId, tenderBudget, government);
        
        escrowContract.depositFunds{value: tenderBudget}(tenderId);

        vm.stopPrank();

        (uint256 amount, address depositor, bool released, uint256 depositedAt, address releasedTo, uint256 releasedAt) = 
            escrowContract.escrows(tenderId);
        
        assertEq(amount, tenderBudget);
        assertEq(depositor, government);
        assertEq(released, false);
        assertGt(depositedAt, 0);
        assertEq(releasedTo, address(0));
        assertEq(releasedAt, 0);
    }

    function test_ShouldRevertIfNonGovernmentTriesToDepositFunds() public {
        uint256 tenderId = _createTender();
        uint256 tenderBudget = 1000000 ether;

        vm.startPrank(vendor1);
        
        vm.expectRevert();
        
        escrowContract.depositFunds{value: tenderBudget}(tenderId);

        vm.stopPrank();
    }

    function test_ShouldRevertIfInsufficientAmount() public {
        uint256 tenderId = _createTender();
        uint256 insufficientAmount = 500000 ether; // Less than budget

        vm.startPrank(government);
        
        vm.expectRevert(abi.encodeWithSelector(EscrowContract.InvalidAmount.selector));
        
        escrowContract.depositFunds{value: insufficientAmount}(tenderId);

        vm.stopPrank();
    }

    function test_ShouldRevertIfZeroAmount() public {
        uint256 tenderId = _createTender();

        vm.startPrank(government);
        
        vm.expectRevert(abi.encodeWithSelector(EscrowContract.InvalidAmount.selector));
        
        escrowContract.depositFunds{value: 0}(tenderId);

        vm.stopPrank();
    }

    // Escrow Management tests
    function test_ShouldAllowGovernmentToReleaseFunds() public {
        uint256 tenderId = _createTender();
        uint256 tenderBudget = 1000000 ether;
        
        // Deposit funds first
        vm.prank(government);
        escrowContract.depositFunds{value: tenderBudget}(tenderId);
        
        // Mark tender as completed
        vm.prank(government);
        tenderContract.markTenderComplete(tenderId);

        uint256 initialBalance = vendor1.balance;

        vm.startPrank(government);
        
        vm.expectEmit(true, true, true, false);
        emit EscrowContract.FundsReleased(tenderId, vendor1, tenderBudget);
        
        escrowContract.releaseFunds(tenderId, payable(vendor1));

        vm.stopPrank();

        (uint256 amount, address depositor, bool released, uint256 depositedAt, address releasedTo, uint256 releasedAt) = 
            escrowContract.escrows(tenderId);
        
        assertEq(amount, tenderBudget);
        assertEq(depositor, government);
        assertEq(released, true);
        assertEq(releasedTo, vendor1);
        assertGt(releasedAt, 0);
        assertEq(vendor1.balance - initialBalance, tenderBudget);
    }

    function test_ShouldAllowGovernmentToRefundFunds() public {
        uint256 tenderId = _createTender();
        uint256 tenderBudget = 1000000 ether;
        
        // Deposit funds first
        vm.prank(government);
        escrowContract.depositFunds{value: tenderBudget}(tenderId);

        uint256 initialBalance = government.balance;

        vm.startPrank(government);
        
        vm.expectEmit(true, true, true, false);
        emit EscrowContract.FundsRefunded(tenderId, government, tenderBudget);
        
        escrowContract.refundFunds(tenderId);

        vm.stopPrank();

        (uint256 amount, address depositor, bool released, uint256 depositedAt, address releasedTo, uint256 releasedAt) = 
            escrowContract.escrows(tenderId);
        
        assertEq(amount, 0);
        assertEq(depositor, address(0));
        assertEq(released, false);
        assertEq(depositedAt, 0);
        assertEq(releasedTo, address(0));
        assertEq(releasedAt, 0);
        assertEq(government.balance - initialBalance, tenderBudget);
    }

    function test_ShouldRevertIfNonGovernmentTriesToReleaseFunds() public {
        uint256 tenderId = _createTender();
        uint256 tenderBudget = 1000000 ether;
        
        // Deposit funds first
        vm.prank(government);
        escrowContract.depositFunds{value: tenderBudget}(tenderId);
        
        // Mark tender as completed
        vm.prank(government);
        tenderContract.markTenderComplete(tenderId);

        vm.startPrank(vendor1);
        
        vm.expectRevert();
        
        escrowContract.releaseFunds(tenderId, payable(vendor1));

        vm.stopPrank();
    }

    function test_ShouldRevertIfNonGovernmentTriesToRefundFunds() public {
        uint256 tenderId = _createTender();
        uint256 tenderBudget = 1000000 ether;
        
        // Deposit funds first
        vm.prank(government);
        escrowContract.depositFunds{value: tenderBudget}(tenderId);

        vm.startPrank(vendor1);
        
        vm.expectRevert();
        
        escrowContract.refundFunds(tenderId);

        vm.stopPrank();
    }

    function test_ShouldRevertIfTryingToReleaseFundsTwice() public {
        uint256 tenderId = _createTender();
        uint256 tenderBudget = 1000000 ether;
        
        // Deposit funds first
        vm.prank(government);
        escrowContract.depositFunds{value: tenderBudget}(tenderId);
        
        // Mark tender as completed
        vm.prank(government);
        tenderContract.markTenderComplete(tenderId);

        vm.startPrank(government);
        escrowContract.releaseFunds(tenderId, payable(vendor1));
        
        vm.expectRevert(abi.encodeWithSelector(EscrowContract.EscrowAlreadyReleased.selector));
        escrowContract.releaseFunds(tenderId, payable(vendor2));
        vm.stopPrank();
    }

    function test_ShouldRevertIfTryingToReleaseFundsBeforeTenderCompletion() public {
        uint256 tenderId = _createTender();
        uint256 tenderBudget = 1000000 ether;
        
        // Deposit funds first
        vm.prank(government);
        escrowContract.depositFunds{value: tenderBudget}(tenderId);

        vm.startPrank(government);
        
        vm.expectRevert(abi.encodeWithSelector(EscrowContract.TenderNotCompleted.selector));
        escrowContract.releaseFunds(tenderId, payable(vendor1));
        
        vm.stopPrank();
    }

    function test_ShouldRevertForInvalidTenderId() public {
        vm.startPrank(government);
        
        vm.expectRevert(abi.encodeWithSelector(EscrowContract.EscrowNotFound.selector));
        escrowContract.releaseFunds(999, payable(vendor1));
        
        vm.stopPrank();
    }

    // Pausable tests
    function test_ShouldAllowPauserToPauseAndUnpause() public {
        vm.startPrank(pauser);
        
        escrowContract.pause();
        assertTrue(escrowContract.paused());

        escrowContract.unpause();
        assertFalse(escrowContract.paused());
        
        vm.stopPrank();
    }

    function test_ShouldNotAllowNonPauserToPause() public {
        vm.startPrank(vendor1);
        
        vm.expectRevert();
        escrowContract.pause();
        
        vm.stopPrank();
    }

    // Helper functions
    function _createTender() internal returns (uint256) {
        string memory description = "Road construction project";
        uint256 budget = 1000000 ether;
        string memory requirementsCid = "QmTestRequirementsCID";
        uint256 serviceFee = 0.01 ether;

        // Give government some ETH to pay the service fee
        vm.deal(government, 2000 ether);

        vm.startPrank(government);
        tenderContract.createTender{value: serviceFee}(description, budget, requirementsCid);
        vm.stopPrank();

        return 1; // First tender ID
    }
}
