// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ITenderContract {
    function addBid(uint256 tenderId, uint256 bidId) external;
    function getTenderDetails(uint256 tenderId) external view returns (
        string memory description,
        uint256 budget,
        string memory requirementsCid,
        bool completed,
        uint256[] memory bidIds
    );
    function getTenderCount() external view returns (uint256);
}
