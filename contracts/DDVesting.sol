// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DDVesting is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    address public DDToken;
    uint256 public VestingStartTime;
    uint256 public totalAmount;
    uint256 public VestingDuration;
    uint256 public secondsPerDay;
    uint256 public dayPerMonth;
    uint256 public PerMonthReleaseAmount;

    mapping(uint8 => bool) public vestingCompleted;
    mapping(address => bool) public isCommunityMember;

    event CommunityMemberAdded(address member, bool status);
    event Claimed(
        uint8 monthClaimed,
        uint256 AmountClaimed,
        address communityMember
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        totalAmount = 200000000 * 10 ** 18; // 20% DD total supply
        VestingDuration = 60; // 5 year or 60 month
        secondsPerDay = 86400;
        dayPerMonth = 30;
        PerMonthReleaseAmount = totalAmount / VestingDuration; // X = n/60
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // Rest of the contract functions remain the same
    // ...

    function setDDTokenAddress(
        address _DDToken
    ) external onlyOwner nonReentrant {
        DDToken = _DDToken;
        VestingStartTime = block.timestamp;
    }

    function setCommunityMember(
        address _member,
        bool _status
    ) external onlyOwner nonReentrant {
        isCommunityMember[_member] = _status;
        emit CommunityMemberAdded(_member, _status);
    }

    function claimToken(uint8 monthCount) external nonReentrant {
        require(isCommunityMember[msg.sender], "not Community Member");
        require(monthCount > 0, "can be claimed from end of first month");
        require(
            monthCount <= VestingDuration,
            "can be claimed for 5 years only"
        );
        require(
            !vestingCompleted[monthCount],
            "this month amount is already claimed"
        );
        uint256 calculatedMonth = (block.timestamp - VestingStartTime) /
            (secondsPerDay * dayPerMonth);
        require(
            calculatedMonth >= monthCount,
            "can not Claim amount for this month"
        );
        vestingCompleted[monthCount] = true;
        IERC20(DDToken).transfer(msg.sender, PerMonthReleaseAmount);
        emit Claimed(monthCount, PerMonthReleaseAmount, msg.sender);
    }

    function currentMonth() public view returns (uint256) {
        return
            (block.timestamp - VestingStartTime) /
            (secondsPerDay * dayPerMonth);
    }
}
