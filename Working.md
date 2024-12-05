# DDToken

Normal transfer

# DDVesting

    # claimToken -
        only community member who has authority given by owner of the contract can claim token every month starting from contract start

        input - month count which month you are claiming ex- 0,1,2,3 till 60

    setCommunityMember -
        owner can add communty member list who has authority to claim token.

    currentMonth -
        any one can check current month for vesting

# VotingSystem

    setWhitelistedContract -
        Only owner can run this function input whitlistcontract address. only those can able to run this run this contract function

    lockTokens -
        only whitelisted contract can call this function on behalf of user

        Input -  useraddres, amount to lock dd, duraction in week

        DD token will be locked and XDD will be given to user calculated with timeof lock

    unlockTokens -
        only whitelisted contract can call this function on behalf of user

        Input -  useraddres

        xDD will be required which is given at time of lock

    addLockupAmount -
        user can increase amount of initial lock using this funtion

        Input -  userAddress, additional amount

    extendLockup -
        user can increase time of initial lock using this funtion

        Input -  userAddress, additional weeks

    setToggledOn -
        user can toggle on off using this function to boost his countdown and function created according to requirment.

        Input -  userAddress, toggle status

    getUserVotingPower -
        read funtion return user current votting power according to the formula provided.

# xDD token -

    normal token working withing voting contract. voting contract has right to mint, burn depending on the requirment

# DMStablecoin -

    mint(address to, uint256 amount)
    Use: Allows community members to create new DM tokens and assign them to a specified address.

    burn(address from, uint256 amount)
    Use: Allows community members to destroy a specific amount of DM tokens from a given address.

    setCommunityMember(address _member, bool _status)
    Use: Enables the contract owner to add or remove addresses from the list of community members who have minting and burning privileges.

# PegStabilityModule

    constructor(address _dmToken)
    Use: Initializes the contract with the address of the DMStablecoin contract.

    addAcceptedStablecoin(address stablecoin)
    Use: Allows the owner to add a new stablecoin to the list of accepted stablecoins for deposits and withdrawals.

    removeAcceptedStablecoin(address stablecoin)
    Use: Allows the owner to remove a stablecoin from the list of accepted stablecoins.

    setSwapFee(uint256 newFee)
    Use: Enables the owner to update the swap fee for withdrawals.

    depositStablecoin(address stablecoin, uint256 amount)
    Use: Allows users to deposit accepted stablecoins and receive an equivalent amount of DM tokens.

    withdrawStablecoin(address stablecoin, uint256 amount)
    Use: Allows users to burn DM tokens and withdraw an equivalent amount of accepted stablecoins, minus the swap fee.

# CollateralVault Contract

    constructor(address _dmToken, address _ddToken)
    Use: Initializes the contract with the addresses of the DMStablecoin and DD token contracts.

    addAcceptedCollateral(address collateral, uint256 ratio, bool _isPSToken)
    Use: Allows the owner to add a new token as accepted collateral, set its collateral ratio, and specify if it's a P&S token.

    depositCollateral(address collateralToken, uint256 amount)
    Use: Enables users to deposit accepted ERC20 tokens as collateral.

    depositCollateralETH(address collateralToken)
    Use: Allows users to deposit ETH as collateral.

    withdrawCollateral(address collateralToken, uint256 amount)
    Use: Permits users to withdraw their ERC20 token collateral, if the remaining collateral is sufficient to cover their loan.

    withdrawCollateralETH(address collateralToken, uint256 amount)
    Use: Allows users to withdraw their ETH collateral, if the remaining collateral is sufficient to cover their loan.

    takeLoan(address collateralToken, uint256 loanAmount)
    Use: Enables users to borrow DM tokens against their deposited collateral.

    repayLoan(address collateralToken, uint256 repayAmount)
    Use: Allows users to repay their DM token loan, reducing their debt.

    lockDD(address collateralToken, uint256 amount)
    Use: Permits users to lock DD tokens for additional benefits on their collateral position.

    isCollateralSufficient(address user, address collateralToken, uint256 withdrawAmount)
    Use: Checks if a user's collateral is sufficient to cover their current loan, considering any potential withdrawal.

    getCollateralPrice(address collateralToken)
    Use: Retrieves the price of a collateral token (currently a placeholder implementation).

# DM Vault

    constructor(address _dmToken)
    Use: Initializes the contract with the address of the DMToken contract.

    depositCollateral(uint256 amount)
    Use: Allows users to deposit DM tokens as collateral into their vault.

    withdrawCollateral(uint256 amount)
    Use: Enables users to withdraw their deposited collateral, provided they maintain the required collateralization ratio.

    mintDM(uint256 amount)
    Use: Allows users to mint new DM tokens against their deposited collateral, maintaining the required collateralization ratio.

    repayDM(uint256 amount)
    Use: Enables users to repay their DM token debt, reducing their outstanding balance.

    liquidate(address user)
    Use: Allows anyone to liquidate a user's vault if its collateralization ratio falls below the liquidation threshold.

# DMSR Contract

    constructor()
    Use: Initializes the contract, creating the "Discount Money" (DM) token with an initial supply of 1 million tokens minted to the contract deployer.

    mint(address to, uint256 amount)
    Use: Allows the contract owner to create and assign new DM tokens to a specified address.

    burn(uint256 amount)
    Use: Enables any token holder to destroy a specific amount of their own DM tokens.

    setDMSavingsRate(uint256 newRate)
    Use: Allows the contract owner to update the annual percentage yield for the savings feature.

    depositToSavings(uint256 amount)
    Use: Permits users to deposit DM tokens into the savings feature to earn interest.

    withdrawFromSavings(uint256 amount)
    Use: Allows users to withdraw their deposited DM tokens along with any accrued interest from the savings feature.

    updateSavings(address account)
    Use: Calculates and applies the accrued interest for a user's savings balance. This function is called internally when depositing or withdrawing, and can also be called externally to update balances.

    getSavingsBalance(address account)
    Use: Provides a view function to check the current savings balance of an account, including any accrued but not yet applied interest.









