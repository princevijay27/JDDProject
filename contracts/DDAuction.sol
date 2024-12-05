// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {DiscountDao} from "./DDToken.sol";

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

contract DDProtocolAuction is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    IERC20 public dmToken;
    DiscountDao public ddToken;
    address public ddVaultAddress;
    address public treasury;
    IAggregatorV3Interface public ddPriceFeeder;
    uint256 public currentId;

    struct Auction {
        uint256 id;
        address vaultOwner;
        uint256 collateralAmount;
        IERC20 collateralToken;
        uint256 finallizedCollateralAmount;
        uint256 debtAmount;
        uint256 liquidationPenalty;
        uint256 startTime;
        uint256 endTime;
        address highestBidder;
        uint256 highestBid;
        bool isReverse;
        bool settled;
    }

    struct SurplusAuction {
        uint256 id;
        uint256 dmAmount;
        uint256 highestDdBid;
        address highestBidder;
        uint256 endTime;
        bool settled;
    }

    struct DebtAuction {
        uint256 id;
        uint256 ddAmount;
        uint256 debtAmount;
        uint256 highestBid;
        address highestBidder;
        uint256 endTime;
        bool settled;
    }

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => SurplusAuction) public surplusAuctions;
    mapping(uint256 => DebtAuction) public debtAuctions;

    uint256 public auctionCount;
    uint256 public surplusAuctionCount;
    uint256 public debtAuctionCount;

    uint256 public constant AUCTION_DURATION = 7 days;
    uint256 public bufferLimit;
    uint256 public buffer;
    uint256 public minimumBidIncrease;

    event AuctionStarted(
        uint256 indexed auctionId,
        address indexed vaultOwner,
        uint256 collateralAmount,
        uint256 debtAmount
    );
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount,
        uint256 collateralAmount
    );
    event AuctionSettled(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 collateralWon,
        uint256 dmPaid
    );
    event SurplusAuctionStarted(uint256 indexed auctionId, uint256 dmAmount);
    event SurplusAuctionBid(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 ddAmount
    );
    event SurplusAuctionSettled(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 dmAmount,
        uint256 ddAmount
    );
    event DebtAuctionStarted(
        uint256 indexed auctionId,
        uint256 dmAmount,
        uint256 initialDdAmount
    );
    event DebtAuctionBid(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 ddAmount
    );
    event DebtAuctionSettled(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 dmAmount,
        uint256 ddAmount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dmToken,
        address _ddToken,
        address _ddVaultAddress,
        address _treasury
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        dmToken = IERC20(_dmToken);
        ddToken = DiscountDao(_ddToken);
        ddVaultAddress = _ddVaultAddress;
        treasury = _treasury;
        currentId = 0;
        bufferLimit = 1000000 * 10 ** 18; // 1 million DM
        buffer = 0;
        minimumBidIncrease = 5; // 5% minimum bid increase
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
    function createAuction(
        address vaultOwner,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 liquidationPenalty,
        address collateralToken
    ) external {
        require(collateralAmount > 0, "collateral must be greater then 0");
        require(
            msg.sender == ddVaultAddress,
            "Only DD vault contract can call this function"
        );
        require(debtAmount > 0, "debt must be greater then 0");
        require(vaultOwner != address(0), "invalid vault owner");
        Auction memory newAuction = Auction({
            id: currentId + 1,
            vaultOwner: vaultOwner,
            collateralAmount: collateralAmount,
            collateralToken: IERC20(collateralToken),
            finallizedCollateralAmount: collateralAmount,
            debtAmount: debtAmount,
            liquidationPenalty: liquidationPenalty,
            startTime: block.timestamp,
            endTime: block.timestamp + AUCTION_DURATION,
            highestBidder: address(0),
            highestBid: 0,
            isReverse: false,
            settled: false
        });

        emit AuctionStarted(
            newAuction.id,
            vaultOwner,
            collateralAmount,
            debtAmount
        );
    }

    function placeBid(
        uint256 auctionId,
        uint256 bidAmount,
        uint256 collateralAmount
    ) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(!auction.settled, "Auction already settled");

        if (!auction.isReverse) {
            require(bidAmount >= auction.highestBid, "Bid too low");
            require(
                dmToken.transferFrom(msg.sender, address(this), bidAmount),
                "DM transfer failed"
            );

            if (auction.highestBidder != address(0)) {
                require(
                    dmToken.transfer(auction.highestBidder, auction.highestBid),
                    "Refund failed"
                );
            }
            auction.highestBidder = msg.sender;
            auction.highestBid = bidAmount;

            if (bidAmount >= auction.debtAmount) {
                require(
                    bidAmount == auction.debtAmount,
                    "Bid must be equal to debtAmount"
                );
                require(
                    collateralAmount <= auction.finallizedCollateralAmount,
                    "Invalid collateral bid"
                );
                auction.isReverse = true;
                auction.finallizedCollateralAmount = collateralAmount;
            }
        } else {
            require(
                bidAmount == auction.debtAmount,
                "Bid must equal debt amount"
            );
            require(
                collateralAmount < auction.finallizedCollateralAmount,
                "Invalid collateral bid"
            );
            require(
                dmToken.transferFrom(msg.sender, address(this), bidAmount),
                "DM transfer failed"
            );
            require(
                dmToken.transfer(auction.highestBidder, auction.highestBid),
                "Refund failed"
            );
            auction.highestBidder = msg.sender;
            auction.highestBid = bidAmount;
            auction.finallizedCollateralAmount = collateralAmount;
        }
        emit BidPlaced(
            auctionId,
            msg.sender,
            bidAmount,
            auction.finallizedCollateralAmount
        );
    }

    function settleAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.endTime, "Auction not yet ended");
        require(!auction.settled, "Auction already settled");

        auction.settled = true;

        if (auction.isReverse) {
            require(
                auction.collateralToken.transfer(
                    auction.highestBidder,
                    auction.finallizedCollateralAmount
                ),
                "Collateral transfer failed"
            );
            uint256 remainingCollateralToken = auction.collateralAmount -
                auction.finallizedCollateralAmount;
            require(
                auction.collateralToken.transfer(
                    auction.vaultOwner,
                    remainingCollateralToken
                ),
                "remaining Collateral transfer failed"
            );
            require(
                dmToken.transfer(treasury, auction.debtAmount),
                "DM transfer failed"
            );
        } else {
            require(auction.highestBidder != address(0), "bid not met");
            require(
                dmToken.transfer(treasury, auction.highestBid),
                "DM transfer failed"
            );
            require(
                auction.collateralToken.transfer(
                    auction.highestBidder,
                    auction.finallizedCollateralAmount
                ),
                "Collateral transfer failed"
            );
            if (auction.highestBid < auction.debtAmount) {
                uint256 debtAmount = auction.debtAmount - auction.highestBid;
                startDebtAuction(debtAmount);
            }
            // dd min karke uska auction karna he yaha par abhi.
        }

        emit AuctionSettled(
            auctionId,
            auction.highestBidder,
            auction.collateralAmount,
            auction.highestBid
        );
    }

    function startSurplusAuction(uint256 surplusAmount) internal {
        surplusAuctions[surplusAuctionCount] = SurplusAuction({
            id: surplusAuctionCount,
            dmAmount: surplusAmount,
            highestDdBid: 0,
            highestBidder: address(0),
            endTime: block.timestamp + AUCTION_DURATION,
            settled: false
        });

        emit SurplusAuctionStarted(surplusAuctionCount, surplusAmount);
        surplusAuctionCount = surplusAuctionCount + 1;
    }

    function bidOnSurplusAuction(
        uint256 auctionId,
        uint256 ddAmount
    ) external nonReentrant {
        SurplusAuction storage auction = surplusAuctions[auctionId];
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(!auction.settled, "Auction already settled");
        require(ddAmount > auction.highestDdBid, "Bid too low");

        require(
            ddToken.transferFrom(msg.sender, address(this), ddAmount),
            "DD transfer failed"
        );

        if (auction.highestBidder != address(0)) {
            require(
                ddToken.transfer(auction.highestBidder, auction.highestDdBid),
                "Refund failed"
            );
        }

        auction.highestDdBid = ddAmount;
        auction.highestBidder = msg.sender;

        emit SurplusAuctionBid(auctionId, msg.sender, ddAmount);
    }

    function settleSurplusAuction(uint256 auctionId) external nonReentrant {
        SurplusAuction storage auction = surplusAuctions[auctionId];
        require(block.timestamp >= auction.endTime, "Auction not yet ended");
        require(!auction.settled, "Auction already settled");

        auction.settled = true;

        if (auction.highestBidder != address(0)) {
            require(
                dmToken.transfer(auction.highestBidder, auction.dmAmount),
                "DM transfer failed"
            );
            ddToken.burn(address(this), auction.highestDdBid);
        }

        emit SurplusAuctionSettled(
            auctionId,
            auction.highestBidder,
            auction.dmAmount,
            auction.highestDdBid
        );
    }

    function startDebtAuction(uint256 debtAmount) internal {
        uint256 ddPrice = getDDPrice();
        uint256 ddAmount = (debtAmount / ddPrice) * 1e8;

        debtAuctions[debtAuctionCount] = DebtAuction({
            id: debtAuctionCount,
            ddAmount: ddAmount,
            debtAmount: debtAmount,
            highestBid: 0,
            highestBidder: address(0),
            endTime: block.timestamp + AUCTION_DURATION,
            settled: false
        });

        ddToken.mint(address(this), ddAmount);
        emit DebtAuctionStarted(debtAuctionCount, debtAmount, ddAmount);
        debtAuctionCount = debtAuctionCount + 1;
    }

    function bidOnDebtAuction(
        uint256 auctionId,
        uint256 dmAmount
    ) external nonReentrant {
        DebtAuction storage auction = debtAuctions[auctionId];
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(!auction.settled, "Auction already settled");
        require(dmAmount > auction.highestBid, "Bid too low");
        require(
            dmToken.transferFrom(msg.sender, address(this), dmAmount),
            "Dm transfer failed"
        );
        if (auction.highestBidder != address(0)) {
            require(
                dmToken.transfer(auction.highestBidder, auction.highestBid),
                "Refund failed"
            );
        }
        auction.highestBid = dmAmount;
        auction.highestBidder = msg.sender;

        emit DebtAuctionBid(auctionId, msg.sender, dmAmount);
    }

    function settleDebtAuction(uint256 auctionId) external nonReentrant {
        DebtAuction storage auction = debtAuctions[auctionId];
        require(block.timestamp >= auction.endTime, "Auction not yet ended");
        require(!auction.settled, "Auction already settled");

        auction.settled = true;

        if (auction.highestBidder != address(0)) {
            require(
                ddToken.transfer(auction.highestBidder, auction.ddAmount),
                "DD transfer failed"
            );
            require(
                dmToken.transfer(treasury, auction.highestBid),
                "DM transfer failed"
            );
        } else {
            // If no bids, the debt remains in the system
            buffer = buffer + auction.debtAmount;
        }

        emit DebtAuctionSettled(
            auctionId,
            auction.highestBidder,
            auction.debtAmount,
            auction.highestBid
        );
    }

    function setBufferLimit(uint256 _bufferLimit) external onlyOwner {
        bufferLimit = _bufferLimit;
    }

    function getAuctionStatus(
        uint256 auctionId
    )
        external
        view
        returns (
            bool exists,
            bool isLive,
            bool isReverse,
            uint256 highestBid,
            address highestBidder
        )
    {
        Auction memory auction = auctions[auctionId];
        exists = auction.startTime > 0;
        isLive =
            exists &&
            !auction.settled &&
            block.timestamp < auction.endTime;
        isReverse = auction.isReverse;
        highestBid = auction.highestBid;
        highestBidder = auction.highestBidder;
    }

    function getSurplusAuctionStatus(
        uint256 auctionId
    )
        external
        view
        returns (
            bool exists,
            bool isLive,
            uint256 highestBid,
            address highestBidder
        )
    {
        SurplusAuction memory auction = surplusAuctions[auctionId];
        exists = auction.endTime > 0;
        isLive =
            exists &&
            !auction.settled &&
            block.timestamp < auction.endTime;
        highestBid = auction.highestDdBid;
        highestBidder = auction.highestBidder;
    }

    function getDebtAuctionStatus(
        uint256 auctionId
    )
        external
        view
        returns (
            bool exists,
            bool isLive,
            uint256 highestBid,
            address highestBidder
        )
    {
        DebtAuction memory auction = debtAuctions[auctionId];
        exists = auction.endTime > 0;
        isLive =
            exists &&
            !auction.settled &&
            block.timestamp < auction.endTime;
        highestBid = auction.highestBid;
        highestBidder = auction.highestBidder;
    }

    function getDDPrice() internal view virtual returns (uint256) {
        (
            ,
            /* uint80 roundID */
            int256 answer /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = ddPriceFeeder.latestRoundData();

        return uint256(answer); // in 8 decimals
    }

    function setDDPriceFeeder(
        address _priceFeeder
    ) external onlyOwner nonReentrant {
        ddPriceFeeder = IAggregatorV3Interface(_priceFeeder);
    }
}
