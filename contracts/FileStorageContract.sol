// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @custom:security-contact altharapacta@gmail.com 
contract FileStorageContract is Pausable, AccessControl {
    bytes32 public constant GOVERNMENT_ROLE = keccak256("GOVERNMENT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant STORAGE_ROLE = keccak256("STORAGE_ROLE");
    
    // Nested mapping: entityType => entityId => CID
    mapping(string => mapping(uint256 => string)) public cids;
    
    // Track which entity types are valid
    mapping(string => bool) public validEntityTypes;
    
    // Track total CIDs stored per entity type
    mapping(string => uint256) public entityTypeCounts;
    
    event CidStored(string indexed entityType, uint256 indexed entityId, string cid);
    event CidUpdated(string indexed entityType, uint256 indexed entityId, string oldCid, string newCid);
    event CidRemoved(string indexed entityType, uint256 indexed entityId, string cid);
    event EntityTypeAdded(string entityType);
    event EntityTypeRemoved(string entityType);
    
    error InvalidEntityType();
    error CidNotFound();
    error CidAlreadyExists();
    error InvalidCid();
    error UnauthorizedAccess();
    
    modifier onlyValidEntityType(string memory entityType) {
        if (!validEntityTypes[entityType]) {
            revert InvalidEntityType();
        }
        _;
    }
    
    modifier onlyValidCid(string memory cid) {
        if (bytes(cid).length == 0) {
            revert InvalidCid();
        }
        _;
    }
    
    constructor(
        address defaultAdmin,
        address government,
        address pauser
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(GOVERNMENT_ROLE, government);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(STORAGE_ROLE, defaultAdmin); // Admin can also store CIDs
        
        // Initialize valid entity types
        validEntityTypes["tender"] = true;
        validEntityTypes["bid"] = true;
        validEntityTypes["proposal"] = true;
        validEntityTypes["requirements"] = true;
        validEntityTypes["specifications"] = true;
    }
    
    /**
     * @dev Stores a CID for a specific entity type and ID
     * @param entityType Type of entity (e.g., "tender", "bid", "proposal")
     * @param entityId ID of the entity
     * @param cid Filecoin CID to store
     */
    function storeCid(
        string memory entityType,
        uint256 entityId,
        string memory cid
    ) external whenNotPaused onlyRole(STORAGE_ROLE) onlyValidEntityType(entityType) onlyValidCid(cid) {
        // Check if CID already exists for this entity
        string memory existingCid = cids[entityType][entityId];
        if (bytes(existingCid).length > 0) {
            revert CidAlreadyExists();
        }
        
        cids[entityType][entityId] = cid;
        entityTypeCounts[entityType]++;
        
        emit CidStored(entityType, entityId, cid);
    }
    
    /**
     * @dev Updates an existing CID for a specific entity
     * @param entityType Type of entity
     * @param entityId ID of the entity
     * @param newCid New Filecoin CID
     */
    function updateCid(
        string memory entityType,
        uint256 entityId,
        string memory newCid
    ) external whenNotPaused onlyRole(STORAGE_ROLE) onlyValidEntityType(entityType) onlyValidCid(newCid) {
        string memory oldCid = cids[entityType][entityId];
        if (bytes(oldCid).length == 0) {
            revert CidNotFound();
        }
        
        cids[entityType][entityId] = newCid;
        
        emit CidUpdated(entityType, entityId, oldCid, newCid);
    }
    
    /**
     * @dev Removes a CID for a specific entity
     * @param entityType Type of entity
     * @param entityId ID of the entity
     */
    function removeCid(
        string memory entityType,
        uint256 entityId
    ) external whenNotPaused onlyRole(STORAGE_ROLE) onlyValidEntityType(entityType) {
        string memory existingCid = cids[entityType][entityId];
        if (bytes(existingCid).length == 0) {
            revert CidNotFound();
        }
        
        delete cids[entityType][entityId];
        entityTypeCounts[entityType]--;
        
        emit CidRemoved(entityType, entityId, existingCid);
    }
    
    /**
     * @dev Retrieves CID for frontend use with Filecoin gateways
     * @param entityType Type of entity
     * @param entityId ID of the entity
     * @return cid Filecoin CID
     */
    function getCid(
        string memory entityType,
        uint256 entityId
    ) external view onlyValidEntityType(entityType) returns (string memory cid) {
        cid = cids[entityType][entityId];
        if (bytes(cid).length == 0) {
            revert CidNotFound();
        }
        return cid;
    }
    
    /**
     * @dev Checks if a CID exists for a specific entity
     * @param entityType Type of entity
     * @param entityId ID of the entity
     * @return exists True if CID exists
     */
    function cidExists(
        string memory entityType,
        uint256 entityId
    ) external view onlyValidEntityType(entityType) returns (bool exists) {
        return bytes(cids[entityType][entityId]).length > 0;
    }
    
    /**
     * @dev Gets multiple CIDs for a range of entity IDs
     * @param entityType Type of entity
     * @param startId Starting entity ID
     * @param endId Ending entity ID
     * @return entityIds Array of entity IDs that have CIDs
     * @return cidArray Array of corresponding CIDs
     */
    function getMultipleCids(
        string memory entityType,
        uint256 startId,
        uint256 endId
    ) external view onlyValidEntityType(entityType) returns (
        uint256[] memory entityIds,
        string[] memory cidArray
    ) {
        require(startId <= endId, "Invalid range");
        require(endId - startId <= 100, "Range too large"); // Prevent gas issues
        
        uint256[] memory tempEntityIds = new uint256[](endId - startId + 1);
        string[] memory tempCids = new string[](endId - startId + 1);
        uint256 count = 0;
        
        for (uint256 i = startId; i <= endId; i++) {
            string memory cid = cids[entityType][i];
            if (bytes(cid).length > 0) {
                tempEntityIds[count] = i;
                tempCids[count] = cid;
                count++;
            }
        }
        
        entityIds = new uint256[](count);
        cidArray = new string[](count);
        
        for (uint256 i = 0; i < count; i++) {
            entityIds[i] = tempEntityIds[i];
            cidArray[i] = tempCids[i];
        }
    }
    
    /**
     * @dev Gets all CIDs for a specific entity type
     * @param entityType Type of entity
     * @return entityIds Array of entity IDs
     * @return cidArray Array of CIDs
     */
    function getAllCidsForType(
        string memory entityType
    ) external view onlyValidEntityType(entityType) returns (
        uint256[] memory entityIds,
        string[] memory cidArray
    ) {
        uint256 totalCount = entityTypeCounts[entityType];
        if (totalCount == 0) {
            return (new uint256[](0), new string[](0));
        }
        
        // This is a simplified implementation
        // In production, you might want to use pagination or events
        uint256[] memory tempEntityIds = new uint256[](totalCount);
        string[] memory tempCids = new string[](totalCount);
        uint256 count = 0;
        
        // Search through a reasonable range (this is a limitation of the current design)
        for (uint256 i = 1; i <= 1000 && count < totalCount; i++) {
            string memory cid = cids[entityType][i];
            if (bytes(cid).length > 0) {
                tempEntityIds[count] = i;
                tempCids[count] = cid;
                count++;
            }
        }
        
        entityIds = new uint256[](count);
        cidArray = new string[](count);
        
        for (uint256 i = 0; i < count; i++) {
            entityIds[i] = tempEntityIds[i];
            cidArray[i] = tempCids[i];
        }
    }
    
    /**
     * @dev Adds a new valid entity type (admin only)
     * @param entityType New entity type to add
     */
    function addEntityType(string memory entityType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(entityType).length > 0, "Empty entity type");
        require(!validEntityTypes[entityType], "Entity type already exists");
        
        validEntityTypes[entityType] = true;
        emit EntityTypeAdded(entityType);
    }
    
    /**
     * @dev Removes an entity type (admin only)
     * @param entityType Entity type to remove
     */
    function removeEntityType(string memory entityType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(validEntityTypes[entityType], "Entity type does not exist");
        require(
            keccak256(bytes(entityType)) != keccak256(bytes("tender")) &&
            keccak256(bytes(entityType)) != keccak256(bytes("bid")),
            "Cannot remove core entity types"
        );
        
        validEntityTypes[entityType] = false;
        emit EntityTypeRemoved(entityType);
    }
    
    /**
     * @dev Grants STORAGE_ROLE to a contract or address
     * @param storageContract Address to grant storage role to
     */
    function grantStorageRole(address storageContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(STORAGE_ROLE, storageContract);
    }
    
    /**
     * @dev Revokes STORAGE_ROLE from a contract or address
     * @param storageContract Address to revoke storage role from
     */
    function revokeStorageRole(address storageContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(STORAGE_ROLE, storageContract);
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
     * @dev Get contract statistics
     * @return totalEntityTypes Number of valid entity types
     * @return totalCids Total CIDs stored across all types
     */
    function getContractStats() external view returns (
        uint256 totalEntityTypes,
        uint256 totalCids
    ) {
        totalCids = 0;
        totalEntityTypes = 0;
        
        // Count entity types and total CIDs
        if (validEntityTypes["tender"]) {
            totalEntityTypes++;
            totalCids += entityTypeCounts["tender"];
        }
        if (validEntityTypes["bid"]) {
            totalEntityTypes++;
            totalCids += entityTypeCounts["bid"];
        }
        if (validEntityTypes["proposal"]) {
            totalEntityTypes++;
            totalCids += entityTypeCounts["proposal"];
        }
        if (validEntityTypes["requirements"]) {
            totalEntityTypes++;
            totalCids += entityTypeCounts["requirements"];
        }
        if (validEntityTypes["specifications"]) {
            totalEntityTypes++;
            totalCids += entityTypeCounts["specifications"];
        }
    }
}
