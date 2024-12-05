// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DMSavingsRate is 
    Initializable, 
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable 
{
    IERC20 public dmToken;
    uint256 public savingsRate;
    uint256 public constant RATE_DENOMINATOR = 1e18;
    uint256 public lastRewardTimestamp;
    address public governanceContract;

    uint256 public accInterestPerShare;
    uint256 public totalDeposits;

    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userRewards;
    mapping(address => uint256) public userAccInterestPerSharePaid;

    // Pending savings rate change
    uint256 public pendingSavingsRate;
    uint256 public savingsRateUpdateTime;

    // Version control
    uint256 public version;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event SavingsRateProposed(uint256 newRate, uint256 effectiveTime);
    event SavingsRateUpdated(uint256 newRate);
    event GovernanceContractUpdated(address newGovernanceContract);
    event ContractUpgraded(uint256 version);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dmToken,
        uint256 initialSavingsRate,
        address _governanceContract
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_governanceContract);
        __UUPSUpgradeable_init();

        require(_dmToken != address(0), "Invalid DM token address");
        require(_governanceContract != address(0), "Invalid governance address");
        require(initialSavingsRate <= RATE_DENOMINATOR, "Invalid rate");

        dmToken = IERC20(_dmToken);
        savingsRate = initialSavingsRate;
        lastRewardTimestamp = block.timestamp;
        governanceContract = _governanceContract;
        version = 1;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        version += 1;
        emit ContractUpgraded(version);
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Deposit amount must be greater than 0");
        updateRewards(msg.sender);
        require(dmToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        userDeposits[msg.sender] += amount;
        totalDeposits += amount;
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(amount <= userDeposits[msg.sender], "Insufficient balance");
        updateRewards(msg.sender);
        userDeposits[msg.sender] -= amount;
        totalDeposits -= amount;
        require(dmToken.transfer(msg.sender, amount), "Transfer failed");
        emit Withdraw(msg.sender, amount);
    }

    function claimRewards() external nonReentrant {
        updateRewards(msg.sender);
        uint256 rewardAmount = userRewards[msg.sender];
        require(rewardAmount > 0, "No rewards to claim");
        userRewards[msg.sender] = 0;
        require(dmToken.transfer(msg.sender, rewardAmount), "Transfer failed");
        emit RewardClaimed(msg.sender, rewardAmount);
    }

    function proposeSavingsRate(uint256 newRate) external onlyOwner {
        require(newRate <= RATE_DENOMINATOR, "Invalid rate");
        pendingSavingsRate = newRate;
        savingsRateUpdateTime = block.timestamp + 24 hours;
        emit SavingsRateProposed(newRate, savingsRateUpdateTime);
    }

    function applySavingsRate() external {
        require(pendingSavingsRate != 0, "No pending rate");
        require(block.timestamp >= savingsRateUpdateTime, "Too early to apply new rate");
        updateAllRewards();
        savingsRate = pendingSavingsRate;
        pendingSavingsRate = 0;
        savingsRateUpdateTime = 0;
        emit SavingsRateUpdated(savingsRate);
    }

    function updateRewards(address user) internal {
        updateAllRewards();
        uint256 userInterest = (userDeposits[user] * accInterestPerShare) / RATE_DENOMINATOR;
        uint256 owed = userInterest - userAccInterestPerSharePaid[user];
        if (owed > 0) {
            userRewards[user] += owed;
        }
        userAccInterestPerSharePaid[user] = userInterest;
    }

    function updateAllRewards() internal {
        if (block.timestamp > lastRewardTimestamp && totalDeposits > 0) {
            uint256 timeElapsed = block.timestamp - lastRewardTimestamp;
            uint256 reward = (totalDeposits * savingsRate * timeElapsed) / (RATE_DENOMINATOR * 365 days);
            accInterestPerShare += (reward * RATE_DENOMINATOR) / totalDeposits;
            lastRewardTimestamp = block.timestamp;
        }
    }

    function getUserBalance(address user) external view returns (uint256 deposit, uint256 reward) {
        deposit = userDeposits[user];
        uint256 _accInterestPerShare = accInterestPerShare;
        if (block.timestamp > lastRewardTimestamp && totalDeposits > 0) {
            uint256 timeElapsed = block.timestamp - lastRewardTimestamp;
            uint256 rewardAccrued = (totalDeposits * savingsRate * timeElapsed) / (RATE_DENOMINATOR * 365 days);
            _accInterestPerShare += (rewardAccrued * RATE_DENOMINATOR) / totalDeposits;
        }
        uint256 userInterest = (deposit * _accInterestPerShare) / RATE_DENOMINATOR;
        reward = userRewards[user] + (userInterest - userAccInterestPerSharePaid[user]);
    }

    function setGovernanceContract(address _governanceContract) external onlyOwner {
        require(_governanceContract != address(0), "Invalid governance address");
        governanceContract = _governanceContract;
        emit GovernanceContractUpdated(_governanceContract);
    }

    function getVersion() external view returns (uint256) {
        return version;
    }
}