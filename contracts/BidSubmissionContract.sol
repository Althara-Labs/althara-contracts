// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ITenderContract} from "./interfaces/ITenderContract.sol";

/// @custom:security-contact altharapacta@gmail.com 
contract BidSubmissionContract is Pausable, AccessControl {
    bytes32 public constant GOVERNMENT_ROLE = keccak256("GOVERNMENT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 private _bidIds;
    
    address public platformWallet;
    uint256 public serviceFee = 0.005 ether; // 0.005 ETH service fee for bid submission
    ITenderContract public tenderContract;
    
    enum BidStatus {
        Pending,    // 0
        Accepted,   // 1
        Rejected    // 2
    }
    
    struct Bid {
        uint256 tenderId;
        address vendor;
        uint256 price;
        string description;
        string proposalCid;
        BidStatus status;
        uint256 submittedAt;
    }
    
    mapping(uint256 => Bid) public bids;
    
    event BidSubmitted(uint256 indexed bidId, uint256 indexed tenderId, address indexed vendor, uint256 price);
    event BidAccepted(uint256 indexed bidId, uint256 indexed tenderId);
    event BidRejected(uint256 indexed bidId, uint256 indexed tenderId);
    event ServiceFeeUpdated(uint256 newFee);
    event PlatformWalletUpdated(address newWallet);
    event TenderContractUpdated(address newTenderContract);
    
    error BidNotFound();
    error BidAlreadyProcessed();
    error InsufficientServiceFee();
    error UnauthorizedAccess();
    error InvalidBidId();
    error TenderNotActive();
    error TenderNotFound();
    error InvalidTenderId();
    
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
    
    constructor(
        address defaultAdmin,
        address government,
        address pauser,
        address _platformWallet,
        address _tenderContract
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(GOVERNMENT_ROLE, government);
        _grantRole(PAUSER_ROLE, pauser);
        
        platformWallet = _platformWallet;
        tenderContract = ITenderContract(_tenderContract);
    }
    
    /**
     * @dev Submits a bid for a tender
     * @param tenderId ID of the tender to bid on
     * @param price Bid price
     * @param description Bid description
     * @param proposalCid IPFS CID for bid proposal document
     */
    function submitBid(
        uint256 tenderId,
        uint256 price,
        string memory description,
        string memory proposalCid
    ) external payable whenNotPaused onlyValidTender(tenderId) onlyActiveTender(tenderId) {
        if (msg.value < serviceFee) {
            revert InsufficientServiceFee();
        }
        
        _bidIds++;
        uint256 bidId = _bidIds;
        
        Bid storage newBid = bids[bidId];
        newBid.tenderId = tenderId;
        newBid.vendor = msg.sender;
        newBid.price = price;
        newBid.description = description;
        newBid.proposalCid = proposalCid;
        newBid.status = BidStatus.Pending;
        newBid.submittedAt = block.timestamp;
        
        // Transfer service fee to platform wallet
        (bool success, ) = payable(platformWallet).call{value: serviceFee}("");
        require(success, "Failed to transfer service fee");
        
        // Refund excess payment
        if (msg.value > serviceFee) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - serviceFee}("");
            require(refundSuccess, "Failed to refund excess payment");
        }
        
        // Link bid to tender
        tenderContract.addBid(tenderId, bidId);
        
        emit BidSubmitted(bidId, tenderId, msg.sender, price);
    }
    
    /**
     * @dev Accepts a bid (government only)
     * @param tenderId ID of the tender
     * @param bidId ID of the bid to accept
     */
    function acceptBid(uint256 tenderId, uint256 bidId) 
        external 
        whenNotPaused 
        onlyRole(GOVERNMENT_ROLE) 
        onlyValidTender(tenderId)
    {
        if (bidId == 0 || bidId > _bidIds) {
            revert InvalidBidId();
        }
        
        Bid storage bid = bids[bidId];
        
        if (bid.tenderId != tenderId) {
            revert InvalidTenderId();
        }
        
        if (bid.status != BidStatus.Pending) {
            revert BidAlreadyProcessed();
        }
        
        bid.status = BidStatus.Accepted;
        
        emit BidAccepted(bidId, tenderId);
    }
    
    /**
     * @dev Rejects a bid (government only)
     * @param tenderId ID of the tender
     * @param bidId ID of the bid to reject
     */
    function rejectBid(uint256 tenderId, uint256 bidId) 
        external 
        whenNotPaused 
        onlyRole(GOVERNMENT_ROLE) 
        onlyValidTender(tenderId)
    {
        if (bidId == 0 || bidId > _bidIds) {
            revert InvalidBidId();
        }
        
        Bid storage bid = bids[bidId];
        
        if (bid.tenderId != tenderId) {
            revert InvalidTenderId();
        }
        
        if (bid.status != BidStatus.Pending) {
            revert BidAlreadyProcessed();
        }
        
        bid.status = BidStatus.Rejected;
        
        emit BidRejected(bidId, tenderId);
    }
    
    /**
     * @dev Returns bid details for frontend viewing
     * @param bidId ID of the bid
     * @return tenderId ID of the tender
     * @return vendor Address of the vendor
     * @return price Bid price
     * @return description Bid description
     * @return proposalCid IPFS CID for proposal
     * @return status Bid status (0=Pending, 1=Accepted, 2=Rejected)
     */
    function getBidDetails(uint256 bidId) 
        external 
        view 
        returns (
            uint256 tenderId,
            address vendor,
            uint256 price,
            string memory description,
            string memory proposalCid,
            uint8 status
        ) 
    {
        if (bidId == 0 || bidId > _bidIds) {
            revert InvalidBidId();
        }
        
        Bid storage bid = bids[bidId];
        return (
            bid.tenderId,
            bid.vendor,
            bid.price,
            bid.description,
            bid.proposalCid,
            uint8(bid.status)
        );
    }
    
    /**
     * @dev Returns complete bid information including submission timestamp
     * @param bidId ID of the bid
     */
    function getBidInfo(uint256 bidId) 
        external 
        view 
        returns (
            uint256 tenderId,
            address vendor,
            uint256 price,
            string memory description,
            string memory proposalCid,
            uint8 status,
            uint256 submittedAt
        ) 
    {
        if (bidId == 0 || bidId > _bidIds) {
            revert InvalidBidId();
        }
        
        Bid storage bid = bids[bidId];
        return (
            bid.tenderId,
            bid.vendor,
            bid.price,
            bid.description,
            bid.proposalCid,
            uint8(bid.status),
            bid.submittedAt
        );
    }
    
    /**
     * @dev Returns the total number of bids submitted
     */
    function getBidCount() external view returns (uint256) {
        return _bidIds;
    }
    
    /**
     * @dev Returns all bids for a specific tender
     * @param tenderId ID of the tender
     * @return bidIds Array of bid IDs for the tender
     */
    function getTenderBids(uint256 tenderId) 
        external 
        view 
        onlyValidTender(tenderId) 
        returns (uint256[] memory bidIds) 
    {
        try tenderContract.getTenderDetails(tenderId) returns (
            string memory,
            uint256,
            string memory,
            bool,
            uint256[] memory tenderBidIds
        ) {
            return tenderBidIds;
        } catch {
            revert TenderNotFound();
        }
    }
    
    /**
     * @dev Returns bids by vendor address
     * @param vendor Address of the vendor
     * @return bidIds Array of bid IDs submitted by the vendor
     */
    function getVendorBids(address vendor) external view returns (uint256[] memory bidIds) {
        uint256 totalBids = _bidIds;
        uint256[] memory tempBidIds = new uint256[](totalBids);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= totalBids; i++) {
            if (bids[i].vendor == vendor) {
                tempBidIds[count] = i;
                count++;
            }
        }
        
        bidIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            bidIds[i] = tempBidIds[i];
        }
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
     * @dev Updates the tender contract address (admin only)
     * @param newTenderContract New tender contract address
     */
    function updateTenderContract(address newTenderContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
     * @dev Check if a bid exists
     * @param bidId ID of the bid
     * @return exists True if bid exists
     */
    function bidExists(uint256 bidId) external view returns (bool exists) {
        return bidId > 0 && bidId <= _bidIds;
    }
    
    /**
     * @dev Get bid status as string
     * @param bidId ID of the bid
     * @return status Status as string
     */
    function getBidStatusString(uint256 bidId) external view returns (string memory status) {
        if (bidId == 0 || bidId > _bidIds) {
            revert InvalidBidId();
        }
        
        BidStatus bidStatus = bids[bidId].status;
        if (bidStatus == BidStatus.Pending) return "Pending";
        if (bidStatus == BidStatus.Accepted) return "Accepted";
        if (bidStatus == BidStatus.Rejected) return "Rejected";
        return "Unknown";
    }
}
