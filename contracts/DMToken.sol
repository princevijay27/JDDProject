// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title DMStablecoin - Upgradeable DM Stablecoin implementation
/// @notice This is the upgradeable version of the DMStablecoin contract
contract DMStablecoin is 
    Initializable, 
    ERC20Upgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable 
{
    /// @notice Mapping to track community members who can mint/burn tokens
    mapping(address => bool) public isCommunityMember;

    /// @notice Event emitted when a community member is added or removed
    event CommunityMemberAdded(address member, bool status);
    
    /// @notice Event emitted when contract version is upgraded
    event ContractUpgraded(uint256 version);

    /// @notice Contract version for tracking upgrades
    uint256 public version;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyCommunityMember() {
        require(isCommunityMember[msg.sender] == true, "not Community Member");
        _;
    }

    /// @notice Initialize the contract, replacing the constructor
    function initialize() public initializer {
        __ERC20_init("De-centralized Money", "DM");
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        version = 1;
    }

    /// @notice Function to mint new tokens
    /// @param to Address to receive the minted tokens
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) 
        external 
        onlyCommunityMember 
        nonReentrant 
    {
        _mint(to, amount);
    }

    /// @notice Function to burn tokens
    /// @param from Address from which to burn tokens
    /// @param amount Amount of tokens to burn
    function burn(address from, uint256 amount) 
        external 
        onlyCommunityMember 
        nonReentrant 
    {
        _burn(from, amount);
    }

    /// @notice Function to add or remove community members
    /// @param _member Address of the member to modify
    /// @param _status Boolean indicating if the address should be a community member
    function setCommunityMember(address _member, bool _status) 
        external 
        onlyOwner 
        nonReentrant 
    {
        require(_member != address(0), "Invalid address");
        isCommunityMember[_member] = _status;
        emit CommunityMemberAdded(_member, _status);
    }

    /// @notice Function to get the current contract version
    function getVersion() external view returns (uint256) {
        return version;
    }

    /// @notice Required by the UUPSUpgradeable module
    /// @dev Only the owner can upgrade the contract
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {
        version += 1;
        emit ContractUpgraded(version);
    }
}