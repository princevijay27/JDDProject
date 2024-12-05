<!-- # DD token -->

# Used In

1.  Vesting Contract - vesting for 60 month of time
2.  Voting Contract - for giving power and mint xDD
3.  PS Contract - give you power to mint p&s token with 1:1
4.  DMSR - holders choose DMSR (increase/decrease on down/up of DM price)

<!-- # Vesting Contract -->

# Used Contract

1.  DD Token

# Used In

    Nil

<!-- # Voting Contract -->

# Used Contract

    1. DD token - locking and for giving power
    2. xDD token - return token when locking dd

# Used In

NIL

<!-- # P&S Token -->

# Used Contract

1.  DD token - give you power to mint p&s token with 1:1

# Used In

1.  DM Stable Coin - P&S token can be used to mint DM with collatoral ratio.
2.  DM stable coin - to pay intrest

<!-- # DM Stablecoin Token -->

# Used Contract

1.  P&S token - give you power to mint DM token with collatoral ratio.
2.  outer stable coin - mint DM with 1:1
3.  Vault Contract - vaults can be used to mint DM

# Used In

1. Vault contract - mint and burn of DM

<!-- # DD Vault Contract -->

# Used Contract

1. DM token - mint burn authority
2.

# Used In

1.  DD Protocol Auction - colleteral can be auctioned when reaches its risk factor

<!-- # DD Protocol Auction -->

# USED Contract

1.  DD Vault - if colleteral is at risk level the colleteral can be auctioned.
2.  DD Token - if after aution we dont have enough fund DD will be minted to fullfil market requirment

<!-- # keeper -->

1.  Their role is to stabilize DM by buy/sell DM to target DM at $1

<!-- # Price Oracle -->

1. Oracle Security Module (OSM) will be implemented for safty purpose if oracle compromise.

# USED In

1.  DD vault for real time price,

# used contract

1.  DD voters choose the oracle

<!-- # Emergency Oracles -->

1. second layer OSM

# USED In

1.  DD vault for real time price,

# used contract

1.  DD voters choose this oracle

<!-- # DMSR - The DM Savings Rate -->

DD holder can manage this contract base rate and DMSR (governance)

# used contract

1.  DM token - staking (any amount, no time boundation)
2.  DD token - holders can choose to decrease/increase the DMSR when DM price is up/down.

<!-- # governance  -->

1. Add a new collateral asset type with a unique set of Risk Parameters.
2. Change the Risk Parameters of one or more existing collateral asset types, or add new
   Risk Parameters to one or more existing collateral asset types.
3. Modify the DM Savings Rate.
4. Choose the set of Oracle Feeds.
5. Choose the set of Emergency Oracles.
6. Trigger Emergency Shutdown.
7. Upgrade the system.
8. Onboard new business partners
9. Adjust standard profit share agreement parameters
10. Modify product and service (P&S) token buyback fees for partners
11. Adjusting Vault Diversification Ratios
