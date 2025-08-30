// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @custom:security-contact altharapacta@gmail.com 
contract TenderContract is Pausable, AccessControl {
    bytes32 public constant GOVERNMENT_ROLE = keccak256("GOVERNMENT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BID_SUBMISSION_ROLE = keccak256("BID_SUBMISSION_ROLE");
    
    uint256 private _tenderIds;
    
    address public platformWallet;
    uint256 public serviceFee = 0.01 ether; // 0.01 ETH service fee
    
    struct Tender {
        string description;
        uint256 budget;
        string requirementsCid;
        bool completed;
        uint256[] bidIds;
        address creator;
        uint256 createdAt;
    }
    
    mapping(uint256 => Tender) public tenders;
    
    event TenderCreated(uint256 indexed tenderId, address indexed creator, string description, uint256 budget);
    event TenderCompleted(uint256 indexed tenderId);
    event BidAdded(uint256 indexed tenderId, uint256 indexed bidId);
    event ServiceFeeUpdated(uint256 newFee);
    event PlatformWalletUpdated(address newWallet);
    
    error TenderNotFound();
    error TenderAlreadyCompleted();
    error InsufficientServiceFee();
    error UnauthorizedAccess();
    error InvalidTenderId();
    
    constructor(address defaultAdmin, address government, address pauser, address _platformWallet) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(GOVERNMENT_ROLE, government);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(BID_SUBMISSION_ROLE, address(this)); // Allow self to add bids
        
        platformWallet = _platformWallet;
    }
    
    /**
     * @dev Creates a new tender with the specified details
     * @param description Description of the tender
     * @param budget Budget allocated for the tender
     * @param requirementsCid IPFS CID for tender requirements document
     */
    function createTender(
        string memory description,
        uint256 budget,
        string memory requirementsCid
    ) external payable whenNotPaused onlyRole(GOVERNMENT_ROLE) {
        if (msg.value < serviceFee) {
            revert InsufficientServiceFee();
        }
        
        _tenderIds++;
        uint256 tenderId = _tenderIds;
        
        Tender storage newTender = tenders[tenderId];
        newTender.description = description;
        newTender.budget = budget;
        newTender.requirementsCid = requirementsCid;
        newTender.completed = false;
        newTender.creator = msg.sender;
        newTender.createdAt = block.timestamp;
        
        // Transfer service fee to platform wallet
        (bool success, ) = payable(platformWallet).call{value: serviceFee}("");
        require(success, "Failed to transfer service fee");
        
        // Refund excess payment
        if (msg.value > serviceFee) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - serviceFee}("");
            require(refundSuccess, "Failed to refund excess payment");
        }
        
        emit TenderCreated(tenderId, msg.sender, description, budget);
    }
    
    /**
     * @dev Returns tender details for frontend viewing
     * @param tenderId ID of the tender
     * @return description Tender description
     * @return budget Tender budget
     * @return requirementsCid IPFS CID for requirements
     * @return completed Completion status
     * @return bidIds Array of bid IDs linked to this tender
     */
    function getTenderDetails(uint256 tenderId) 
        external 
        view 
        returns (
            string memory description,
            uint256 budget,
            string memory requirementsCid,
            bool completed,
            uint256[] memory bidIds
        ) 
    {
        if (tenderId == 0 || tenderId > _tenderIds) {
            revert InvalidTenderId();
        }
        
        Tender storage tender = tenders[tenderId];
        return (
            tender.description,
            tender.budget,
            tender.requirementsCid,
            tender.completed,
            tender.bidIds
        );
    }
    
    /**
     * @dev Marks a tender as completed
     * @param tenderId ID of the tender to mark as completed
     */
    function markTenderComplete(uint256 tenderId) 
        external 
        whenNotPaused 
        onlyRole(GOVERNMENT_ROLE) 
    {
        if (tenderId == 0 || tenderId > _tenderIds) {
            revert InvalidTenderId();
        }
        
        Tender storage tender = tenders[tenderId];
        
        if (tender.completed) {
            revert TenderAlreadyCompleted();
        }
        
        tender.completed = true;
        
        emit TenderCompleted(tenderId);
    }
    
    /**
     * @dev Internal function to add a bid to a tender (called by BidSubmissionContract)
     * @param tenderId ID of the tender
     * @param bidId ID of the bid to link
     */
    function addBid(uint256 tenderId, uint256 bidId) 
        external 
        whenNotPaused 
        onlyRole(BID_SUBMISSION_ROLE) 
    {
        if (tenderId == 0 || tenderId > _tenderIds) {
            revert InvalidTenderId();
        }
        
        Tender storage tender = tenders[tenderId];
        
        if (tender.completed) {
            revert TenderAlreadyCompleted();
        }
        
        tender.bidIds.push(bidId);
        
        emit BidAdded(tenderId, bidId);
    }
    
    /**
     * @dev Returns the total number of tenders created
     */
    function getTenderCount() external view returns (uint256) {
        return _tenderIds;
    }
    
    /**
     * @dev Returns tender information including creator and creation timestamp
     * @param tenderId ID of the tender
     */
    function getTenderInfo(uint256 tenderId) 
        external 
        view 
        returns (
            string memory description,
            uint256 budget,
            string memory requirementsCid,
            bool completed,
            uint256[] memory bidIds,
            address creator,
            uint256 createdAt
        ) 
    {
        if (tenderId == 0 || tenderId > _tenderIds) {
            revert InvalidTenderId();
        }
        
        Tender storage tender = tenders[tenderId];
        return (
            tender.description,
            tender.budget,
            tender.requirementsCid,
            tender.completed,
            tender.bidIds,
            tender.creator,
            tender.createdAt
        );
    }
    
    /**
     * @dev Updates the service fee (admin only)
     * @param newFee New service fee amount
     */
    function updateServiceFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        serviceFee = newFee;
        emit ServiceFeeUpdated(newFee);
    }
    
    /**
     * @dev Updates the platform wallet address (admin only)
     * @param newWallet New platform wallet address
     */
    function updatePlatformWallet(address newWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newWallet != address(0), "Invalid wallet address");
        platformWallet = newWallet;
        emit PlatformWalletUpdated(newWallet);
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
     * @dev Grant BID_SUBMISSION_ROLE to BidSubmissionContract
     * @param bidContract Address of the BidSubmissionContract
     */
    function grantBidSubmissionRole(address bidContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BID_SUBMISSION_ROLE, bidContract);
    }
    
    /**
     * @dev Revoke BID_SUBMISSION_ROLE from a contract
     * @param bidContract Address of the contract to revoke role from
     */
    function revokeBidSubmissionRole(address bidContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BID_SUBMISSION_ROLE, bidContract);
    }
}
