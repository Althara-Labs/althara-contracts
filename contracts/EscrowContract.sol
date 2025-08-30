// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITenderContract} from "./interfaces/ITenderContract.sol";

/// @custom:security-contact altharapacta@gmail.com 
contract EscrowContract is Pausable, AccessControl, ReentrancyGuard {
    bytes32 public constant GOVERNMENT_ROLE = keccak256("GOVERNMENT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    ITenderContract public tenderContract;
    
    struct Escrow {
        uint256 amount;
        address depositor;
        bool released;
        uint256 depositedAt;
        address releasedTo;
        uint256 releasedAt;
    }
    
    mapping(uint256 => Escrow) public escrows;
    
    event FundsDeposited(uint256 indexed tenderId, uint256 amount, address indexed depositor);
    event FundsReleased(uint256 indexed tenderId, address indexed vendor, uint256 amount);
    event FundsRefunded(uint256 indexed tenderId, address indexed depositor, uint256 amount);
    event TenderContractUpdated(address newTenderContract);
    
    error EscrowNotFound();
    error EscrowAlreadyReleased();
    error EscrowNotReleased();
    error InsufficientFunds();
    error TenderNotCompleted();
    error TenderNotActive();
    error TenderNotFound();
    error InvalidTenderId();
    error InvalidAmount();
    error UnauthorizedAccess();
    
    modifier onlyValidTender(uint256 tenderId) {
        if (tenderId == 0) {
            revert InvalidTenderId();
        }
        _;
    }
    
    modifier onlyActiveTender(uint256 tenderId) {
        // Check if tender exists and is not completed
        try tenderContract.getTenderDetails(tenderId) returns (
            string memory,
            uint256,
            string memory,
            bool completed,
            uint256[] memory
        ) {
            if (completed) {
                revert TenderNotActive();
            }
        } catch {
            revert TenderNotFound();
        }
        _;
    }
    
    modifier onlyCompletedTender(uint256 tenderId) {
        // Check if tender exists and is completed
        try tenderContract.getTenderDetails(tenderId) returns (
            string memory,
            uint256,
            string memory,
            bool completed,
            uint256[] memory
        ) {
            if (!completed) {
                revert TenderNotCompleted();
            }
        } catch {
            revert TenderNotFound();
        }
        _;
    }
    
    constructor(
        address defaultAdmin,
        address government,
        address pauser,
        address _tenderContract
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(GOVERNMENT_ROLE, government);
        _grantRole(PAUSER_ROLE, pauser);
        
        tenderContract = ITenderContract(_tenderContract);
    }
    
    /**
     * @dev Deposits funds for a tender (government only)
     * @param tenderId ID of the tender to deposit funds for
     */
    function depositFunds(uint256 tenderId) 
        external 
        payable 
        whenNotPaused 
        nonReentrant 
        onlyRole(GOVERNMENT_ROLE) 
        onlyValidTender(tenderId) 
        onlyActiveTender(tenderId) 
    {
        if (msg.value == 0) {
            revert InvalidAmount();
        }
        
        // Check if escrow already exists
        if (escrows[tenderId].amount > 0) {
            revert EscrowAlreadyReleased();
        }
        
        // Get tender budget to validate deposit amount
        try tenderContract.getTenderDetails(tenderId) returns (
            string memory,
            uint256 budget,
            string memory,
            bool,
            uint256[] memory
        ) {
            if (msg.value != budget) {
                revert InvalidAmount();
            }
        } catch {
            revert TenderNotFound();
        }
        
        Escrow storage newEscrow = escrows[tenderId];
        newEscrow.amount = msg.value;
        newEscrow.depositor = msg.sender;
        newEscrow.released = false;
        newEscrow.depositedAt = block.timestamp;
        
        emit FundsDeposited(tenderId, msg.value, msg.sender);
    }
    
    /**
     * @dev Releases funds to vendor after tender completion (government only)
     * @param tenderId ID of the tender
     * @param vendor Address of the vendor to release funds to
     */
    function releaseFunds(uint256 tenderId, address payable vendor) 
        external 
        whenNotPaused 
        nonReentrant 
        onlyRole(GOVERNMENT_ROLE) 
        onlyValidTender(tenderId) 
        onlyCompletedTender(tenderId) 
    {
        if (vendor == address(0)) {
            revert InvalidTenderId();
        }
        
        Escrow storage escrow = escrows[tenderId];
        
        if (escrow.amount == 0) {
            revert EscrowNotFound();
        }
        
        if (escrow.released) {
            revert EscrowAlreadyReleased();
        }
        
        uint256 amount = escrow.amount;
        escrow.released = true;
        escrow.releasedTo = vendor;
        escrow.releasedAt = block.timestamp;
        
        // Transfer funds to vendor
        (bool success, ) = vendor.call{value: amount}("");
        require(success, "Failed to release funds");
        
        emit FundsReleased(tenderId, vendor, amount);
    }
    
    /**
     * @dev Refunds funds to depositor if tender is not completed (government only)
     * @param tenderId ID of the tender
     */
    function refundFunds(uint256 tenderId) 
        external 
        whenNotPaused 
        nonReentrant 
        onlyRole(GOVERNMENT_ROLE) 
        onlyValidTender(tenderId) 
        onlyActiveTender(tenderId) 
    {
        Escrow storage escrow = escrows[tenderId];
        
        if (escrow.amount == 0) {
            revert EscrowNotFound();
        }
        
        if (escrow.released) {
            revert EscrowAlreadyReleased();
        }
        
        uint256 amount = escrow.amount;
        address depositor = escrow.depositor;
        
        // Clear escrow data
        escrow.amount = 0;
        escrow.depositor = address(0);
        escrow.depositedAt = 0;
        
        // Transfer funds back to depositor
        (bool success, ) = payable(depositor).call{value: amount}("");
        require(success, "Failed to refund funds");
        
        emit FundsRefunded(tenderId, depositor, amount);
    }
    
    /**
     * @dev Returns escrow balance and status for a tender
     * @param tenderId ID of the tender
     * @return amount Amount deposited
     * @return depositor Address of the depositor
     * @return released Whether funds have been released
     * @return depositedAt Timestamp when funds were deposited
     * @return releasedTo Address funds were released to (if released)
     * @return releasedAt Timestamp when funds were released (if released)
     */
    function getEscrowBalance(uint256 tenderId) 
        external 
        view 
        onlyValidTender(tenderId) 
        returns (
            uint256 amount,
            address depositor,
            bool released,
            uint256 depositedAt,
            address releasedTo,
            uint256 releasedAt
        ) 
    {
        Escrow storage escrow = escrows[tenderId];
        return (
            escrow.amount,
            escrow.depositor,
            escrow.released,
            escrow.depositedAt,
            escrow.releasedTo,
            escrow.releasedAt
        );
    }
    
    /**
     * @dev Returns escrow status as string
     * @param tenderId ID of the tender
     * @return status Status as string
     */
    function getEscrowStatusString(uint256 tenderId) 
        external 
        view 
        onlyValidTender(tenderId) 
        returns (string memory status) 
    {
        Escrow storage escrow = escrows[tenderId];
        
        if (escrow.amount == 0) {
            return "No Escrow";
        }
        
        if (escrow.released) {
            return "Released";
        }
        
        return "Deposited";
    }
    
    /**
     * @dev Check if escrow exists for a tender
     * @param tenderId ID of the tender
     * @return exists True if escrow exists
     */
    function escrowExists(uint256 tenderId) 
        external 
        view 
        onlyValidTender(tenderId) 
        returns (bool exists) 
    {
        return escrows[tenderId].amount > 0;
    }
    
    /**
     * @dev Check if escrow is released for a tender
     * @param tenderId ID of the tender
     * @return released True if escrow is released
     */
    function isEscrowReleased(uint256 tenderId) 
        external 
        view 
        onlyValidTender(tenderId) 
        returns (bool released) 
    {
        return escrows[tenderId].released;
    }
    
    /**
     * @dev Get total escrow balance across all tenders
     * @return totalBalance Total amount in escrow
     */
    function getTotalEscrowBalance() external view returns (uint256 totalBalance) {
        uint256 tenderCount = tenderContract.getTenderCount();
        
        for (uint256 i = 1; i <= tenderCount; i++) {
            Escrow storage escrow = escrows[i];
            if (escrow.amount > 0 && !escrow.released) {
                totalBalance += escrow.amount;
            }
        }
    }
    
    /**
     * @dev Get escrow details for multiple tenders
     * @param tenderIds Array of tender IDs
     * @return amounts Array of amounts
     * @return depositors Array of depositors
     * @return released Array of release status
     */
    function getMultipleEscrowBalances(uint256[] calldata tenderIds) 
        external 
        view 
        returns (
            uint256[] memory amounts,
            address[] memory depositors,
            bool[] memory released
        ) 
    {
        amounts = new uint256[](tenderIds.length);
        depositors = new address[](tenderIds.length);
        released = new bool[](tenderIds.length);
        
        for (uint256 i = 0; i < tenderIds.length; i++) {
            Escrow storage escrow = escrows[tenderIds[i]];
            amounts[i] = escrow.amount;
            depositors[i] = escrow.depositor;
            released[i] = escrow.released;
        }
    }
    
    /**
     * @dev Updates the tender contract address (admin only)
     * @param newTenderContract New tender contract address
     */
    function updateTenderContract(address newTenderContract) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newTenderContract != address(0), "Invalid contract address");
        tenderContract = ITenderContract(newTenderContract);
        emit TenderContractUpdated(newTenderContract);
    }
    
    /**
     * @dev Pause the contract (emergency stop)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Emergency function to withdraw stuck funds (admin only)
     * @param amount Amount to withdraw
     * @param to Address to send funds to
     */
    function emergencyWithdraw(uint256 amount, address payable to) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
    {
        require(to != address(0), "Invalid recipient address");
        require(amount <= address(this).balance, "Insufficient contract balance");
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "Failed to withdraw funds");
    }
    
    /**
     * @dev Get contract balance
     * @return balance Current contract balance
     */
    function getContractBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }
    
    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {
        revert("Direct deposits not allowed");
    }
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {
        revert("Function not found");
    }
}
