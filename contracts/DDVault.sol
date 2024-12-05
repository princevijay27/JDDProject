// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Use upgradeable versions of contracts
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IDMStablecoin.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IAuctionContract {
    function createAuction(
        address vaultOwner,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 liquidationPenalty,
        address collateralToken
    ) external returns (uint256);
}

interface IAggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/**
    1. A user can create a vault by depositing collateral tokens.
    2. The vault has a set list of collateral tokens that can be used.
    3. The vault has set liquidation ratios for each collateral token.
    4. The vault can generate DM stablecoins by depositing collateral.
    5. The vault can repay DM stablecoins to unlock collateral.
    6. The liquidation can happen
 */
contract DDVault is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    struct Vault {
        address owner;
        address collateralToken;
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 stabilityFeeAccrued;
        uint256 lastUpdateTime;
    }

    IDMStablecoin public DMToken;
    mapping(uint256 => Vault) public vaults;
    uint256 public nextVaultId;
    mapping(address => bool) public allowedCollateral;
    mapping(address => uint256) public liquidationRatio;
    mapping(address => IAggregatorV3Interface) public priceFeeds;
    uint256 public stabilityFeeRate;

    address public oracleSecurityModule;

    IAuctionContract public auctionContract;
    uint256 public liquidationPenalty; // in basis points (e.g., 1000 = 10%)
    uint256 public auctionDuration;

    event VaultCreated(uint256 vaultId, address owner);
    event CollateralAdded(uint256 vaultId, uint256 amount);
    event DMGenerated(uint256 vaultId, uint256 amount);
    event DebtRepaid(uint256 vaultId, uint256 amount);
    event CollateralWithdrawn(uint256 vaultId, uint256 amount);
    event VaultLiquidated(
        uint256 indexed vaultId,
        uint256 indexed auctionId,
        uint256 collateralAmount,
        uint256 debtAmount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _DMToken,
        address _oracleSecurityModule,
        address _owner
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        DMToken = IDMStablecoin(_DMToken);
        oracleSecurityModule = _oracleSecurityModule;
        liquidationPenalty = 1000; // 10% default liquidation penalty
        auctionDuration = 7 days; // 7 days default auction duration

        // Transfer ownership to the specified owner
        transferOwnership(_owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier onlyGovernance() {
        require(msg.sender == owner(), "Not authorized");
        _;
    }

    function createVault(address _collateralToken) external returns (uint256) {
        require(nextVaultId < type(uint256).max, "Vault limit reached");
        require(
            allowedCollateral[_collateralToken],
            "Collateral token not allowed"
        );
        uint256 vaultId = nextVaultId++;
        vaults[vaultId] = Vault({
            owner: msg.sender,
            collateralToken: _collateralToken,
            collateralAmount: 0,
            debtAmount: 0,
            stabilityFeeAccrued: 0,
            lastUpdateTime: block.timestamp
        });
        emit VaultCreated(vaultId, msg.sender);
        return vaultId;
    }

    function addCollateral(
        uint256 vaultId,
        uint256 amount
    ) external nonReentrant {
        Vault storage vault = vaults[vaultId];
        require(vault.owner == msg.sender, "Not vault owner");
        IERC20(vault.collateralToken).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        vault.collateralAmount += amount;
        emit CollateralAdded(vaultId, amount);
    }

    function generateDM(uint256 vaultId, uint256 amount) external nonReentrant {
        Vault storage vault = vaults[vaultId];
        require(vault.owner == msg.sender, "Not vault owner");
        // Check the collateral is sufficient after adding the debt
        require(
            isCollateralSufficient(vaultId, amount),
            "Insufficient collateral"
        );

        updateStabilityFee(vaultId); // Interest calculation since last debt update
        vault.debtAmount += amount;
        DMToken.mint(msg.sender, amount);
        emit DMGenerated(vaultId, amount);
    }

    function repayDebt(uint256 vaultId, uint256 amount) external nonReentrant {
        Vault storage vault = vaults[vaultId];
        updateStabilityFee(vaultId); // Interest calculation since last debt update
        uint256 totalDebt = vault.debtAmount + vault.stabilityFeeAccrued; // Total debt including interest
        require(amount <= totalDebt, "Amount exceeds debt");

        DMToken.burn(msg.sender, amount);
        if (amount > vault.stabilityFeeAccrued) {
            vault.debtAmount -= (amount - vault.stabilityFeeAccrued);
            vault.stabilityFeeAccrued = 0;
        } else {
            vault.stabilityFeeAccrued -= amount;
        }
        emit DebtRepaid(vaultId, amount);
    }

    function withdrawCollateral(
        uint256 vaultId,
        uint256 amount
    ) external nonReentrant {
        Vault storage vault = vaults[vaultId];
        require(vault.owner == msg.sender, "Not vault owner");
        // Update stability fee before checking collateral sufficiency
        updateStabilityFee(vaultId);
        vault.collateralAmount -= amount;
        require(
            isCollateralSufficient(vaultId, 0),
            "Insufficient collateral after withdrawal"
        );

        IERC20(vault.collateralToken).transfer(msg.sender, amount);
        emit CollateralWithdrawn(vaultId, amount);
    }

    function liquidateVault(uint256 vaultId) external nonReentrant {
        Vault storage vault = vaults[vaultId];
        // Update stability fee before checking vault safety
        updateStabilityFee(vaultId);
        require(isVaultUnsafe(vaultId), "Vault is safe");

        uint256 totalDebt = vault.debtAmount + vault.stabilityFeeAccrued;
        uint256 liquidationAmount = totalDebt +
            (totalDebt * liquidationPenalty) /
            10000;

        uint256 auctionId = auctionContract.createAuction(
            vault.owner,
            vault.collateralAmount,
            vault.debtAmount,
            liquidationAmount,
            vault.collateralToken
        );

        // Transfer collateral to the auction contract
        IERC20(vault.collateralToken).transfer(
            address(auctionContract),
            vault.collateralAmount
        );

        // Reset the vault
        uint256 collateralAmount = vault.collateralAmount; // Save for event
        vault.collateralAmount = 0;
        vault.debtAmount = 0;
        vault.stabilityFeeAccrued = 0;

        emit VaultLiquidated(
            vaultId,
            auctionId,
            collateralAmount,
            liquidationAmount
        );
    }

    // Governance functions to update parameters
    function setLiquidationPenalty(uint256 _penalty) external onlyGovernance {
        liquidationPenalty = _penalty;
    }

    function setAuctionDuration(uint256 _duration) external onlyGovernance {
        auctionDuration = _duration;
    }

    function setAuctionContract(
        address _auctionContract
    ) external onlyGovernance {
        auctionContract = IAuctionContract(_auctionContract);
    }

    /**
        @dev Calculates the interest on the amount borrowed
     */
    function updateStabilityFee(uint256 vaultId) internal {
        uint256 feeAccrued = getStabilityFee(vaultId);
        vaults[vaultId].stabilityFeeAccrued += feeAccrued;
        vaults[vaultId].lastUpdateTime = block.timestamp;
    }

    /**
        @dev Returns the stability fee accrued since last update
     */
    function getStabilityFee(uint256 vaultId) public view returns (uint256) {
        Vault memory vault = vaults[vaultId];
        uint256 timePassed = block.timestamp - vault.lastUpdateTime;
        return
            (vault.debtAmount * stabilityFeeRate * timePassed) /
            (365 days * 10000);
    }

    /**
        @dev Checks if ((debtAmt * collateralization ratio) <= collateral Value)
     */
    function isCollateralSufficient(
        uint256 vaultId,
        uint256 additionalDebt
    ) internal view returns (bool) {
        Vault storage vault = vaults[vaultId];
        uint256 totalDebt = vault.debtAmount +
            vault.stabilityFeeAccrued +
            additionalDebt;
        uint256 collateralValue = getCollateralValue(
            vault.collateralToken,
            vault.collateralAmount
        );
        uint256 ratio = liquidationRatio[vault.collateralToken];
        return collateralValue * 100 >= totalDebt * ratio;
    }

    function getCollateralValue(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 price = getCollateralPrice(token);
        return (amount * price) / 1e8; // Price is in 8 decimal precision
    }

    function getCollateralPrice(address token) internal view returns (uint256) {
        IAggregatorV3Interface feeder = priceFeeds[token];
        return getPrice(feeder); // in 8 decimals
    }

    function getPrice(
        IAggregatorV3Interface _feederAddress
    ) internal view virtual returns (uint256) {
        (
            ,
            int256 answer,
            ,
            ,

        ) = _feederAddress.latestRoundData();

        return uint256(answer); // in 8 decimals
    }

    function isVaultUnsafe(uint256 vaultId) internal view returns (bool) {
        return !isCollateralSufficient(vaultId, 0);
    }

    // Governance functions to update parameters
    function setLiquidationRatio(
        address _token,
        uint256 _ratio
    ) external onlyGovernance {
        liquidationRatio[_token] = _ratio;
    }

    function setAllowedCollateralTokens(
        address _token,
        IAggregatorV3Interface _priceFeed
    ) external onlyGovernance {
        allowedCollateral[_token] = true;
        priceFeeds[_token] = _priceFeed;
    }

    function setStabilityFeeRate(uint256 _rate) external onlyGovernance {
        stabilityFeeRate = _rate;
    }
}
