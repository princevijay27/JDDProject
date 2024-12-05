// Sources flattened with hardhat v2.19.5 https://hardhat.org

// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts/utils/ReentrancyGuard.sol@v5.0.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}


// File contracts/DDVesting.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

contract DDVesting is ReentrancyGuard {
    
    address public DDToken;
    address owner;
    uint256 public VestingStartTime;
    uint256 public totalAmount = 200000000 * 10**18;  // 20% DD total supply
    uint256 public VestingDuration = 60;    // 5 year or 60 month
    uint256 public secondsPerDay = 86400;
    uint256 public dayPerMonth = 30; 
    uint256 public PerMonthReleaseAmount = totalAmount/VestingDuration;   // X = n/60

    mapping(uint8 => bool) public vestingCompleted;
    mapping(address => bool) public isCommunityMember;

    modifier onlyCommunityMember() {
        require(isCommunityMember[msg.sender] == true, "not Community Member");
        _;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "not owner");
        _;
    }

    event CommunityMemberAdded(address member, bool status);

    event Claimed(
        uint8 monthClaimed,
        uint256 AmountClaimed,
        address communityMember
    );

    constructor(address _owner) {
        owner = _owner;
    }

    function setDDTokenAddress(address _DDToken) external onlyOwner nonReentrant {
        DDToken = _DDToken;
        VestingStartTime = block.timestamp;
    }

    // owner can add communty member list who has authority to claim token. 
    function setCommunityMember(address _member, bool _status) external onlyOwner nonReentrant {
        isCommunityMember[_member] = _status;
        emit CommunityMemberAdded(_member, _status);
    }

    // only community member who has authority given by owner of the contract can claim token every month starting from contract start
    function claimToken(uint8 monthCount) external nonReentrant onlyCommunityMember {
        require(monthCount > 0, "can be claimed from end of first month");
        require(monthCount <= VestingDuration, "can be claimed for 5 years only");
        require(vestingCompleted[monthCount] == false, "this month amount is already claimed");
        uint256 calculatedMonth = (block.timestamp - VestingStartTime)/(secondsPerDay * dayPerMonth);
        require(calculatedMonth >= monthCount,"can not Claim amount for this month");
        vestingCompleted[monthCount] = true;
        IERC20(DDToken).transfer(msg.sender, PerMonthReleaseAmount);
        emit Claimed(monthCount, PerMonthReleaseAmount, msg.sender);
    }

    // any one can check current month for vesting 
    function currentMonth() public view returns(uint256){
        return (block.timestamp - VestingStartTime)/(secondsPerDay * dayPerMonth);
    }
}
