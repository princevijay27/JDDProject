// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DMStablecoin } from "./DMToken.sol";

contract PegStabilityModule is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    DMStablecoin public dmToken;
    address public treasury;
    mapping(address => bool) public acceptedStablecoins;
    uint256 public swapFee; // 10 basis points = 0.1%
    uint256 public maxSwapFee;

    // Events remain unchanged
    event StablecoinDeposited(address indexed user, address indexed token, uint256 amount);
    event StablecoinWithdrawn(address indexed user, address indexed token, uint256 amount);
    event SwapFeeUpdated(uint256 newFee);
    event TreasuryUpdated(address newTreasury);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Disable the implementation contract's initializers
        _disableInitializers();
    }

    // Initializer function instead of constructor
    function initialize(
        address _dmToken,
        address _treasury,
        uint256 _maxSwapFees
    ) public initializer {
        require(_dmToken != address(0), "Invalid DM token address");
        require(_treasury != address(0), "Invalid treasury address");
        require(_maxSwapFees > 0, "Max Fees must be greater than 0");

        // Initialize parent contracts
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        dmToken = DMStablecoin(_dmToken);
        treasury = _treasury;
        maxSwapFee = _maxSwapFees;
        swapFee = 10; // Initialize to 10 basis points
    }

    // Authorization for upgrades: only the owner can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Functions remain largely the same, but remove the constructor
    function addAcceptedStablecoin(address stablecoin) external onlyOwner {
        require(stablecoin != address(0), "Invalid stablecoin address");
        acceptedStablecoins[stablecoin] = true;
    }

    function removeAcceptedStablecoin(address stablecoin) external onlyOwner {
        acceptedStablecoins[stablecoin] = false;
    }

    function setSwapFee(uint256 newFee) external onlyOwner {
        require(newFee <= maxSwapFee, "Fee too high");
        swapFee = newFee;
        emit SwapFeeUpdated(newFee);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function depositStablecoin(address stablecoin, uint256 amount) external nonReentrant {
        require(acceptedStablecoins[stablecoin], "Stablecoin not accepted");
        require(amount > 0, "Amount must be greater than 0");
        require(IERC20(stablecoin).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        dmToken.mint(msg.sender, amount);
        emit StablecoinDeposited(msg.sender, stablecoin, amount);
    }

    function withdrawStablecoin(address stablecoin, uint256 amount) external nonReentrant {
        require(acceptedStablecoins[stablecoin], "Stablecoin not accepted");
        require(amount > 0, "Amount must be greater than 0");
        uint256 fee = (amount * swapFee) / 10000;
        uint256 amountAfterFee = amount - fee;
        dmToken.burn(msg.sender, amount);
        require(IERC20(stablecoin).transfer(treasury, fee), "Fee transfer failed");
        require(IERC20(stablecoin).transfer(msg.sender, amountAfterFee), "Transfer failed");
        emit StablecoinWithdrawn(msg.sender, stablecoin, amountAfterFee);
    }

    function rescueTokens(IERC20 token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(token.transfer(to, amount), "Token rescue failed");
    }
}
