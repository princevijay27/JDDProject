// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DiscountDao is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    mapping(address => bool) public isAuctionContract;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _developmentAddress,
        address _community,
        address _businesses,
        address _airdropAddress,
        address _vestingContract,
        address initialOwner
    ) public initializer {
        __ERC20_init("Discount Dao", "DD");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        uint256 totalSupply = 1000000000 * 10 ** decimals();

        _mint(_developmentAddress, (30 * totalSupply) / 100); // 30% development Team
        _mint(_businesses, (20 * totalSupply) / 100); // 20% businesses & partner
        _mint(_community, (25 * totalSupply) / 100); // 25% community
        _mint(_vestingContract, (20 * totalSupply) / 100); // 20% community with 5 year vesting
        _mint(_airdropAddress, (5 * totalSupply) / 100); // 5% Airdrop community rewards
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier onlyAuctionContract() {
        require(isAuctionContract[msg.sender] == true, "not Auction Contract");
        _;
    }

    event AuctionContractAdded(address member, bool status);

    function mint(address to, uint256 amount) external onlyAuctionContract {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyAuctionContract {
        _burn(from, amount);
    }

    function setAuctionContract(address _address, bool _status) external onlyOwner {
        isAuctionContract[_address] = _status;
        emit AuctionContractAdded(_address, _status);
    }
}