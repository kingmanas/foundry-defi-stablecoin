// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/// @title DSCEngine
/// @author BlockBuddy
/// @notice Handles all the logic of Stable Coin BDY , based on MakerDAO DSS system.

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    /////////////////////////////////
    ////////////ERRORS///////////////
    /////////////////////////////////

    error DSCEngine__MoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressLengthShouldBeSame();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOkay();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////////////////////
    ///////////STATE VARIABLES////////////
    //////////////////////////////////////

    // we must avoid magic numbers in our code
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATOR_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    DecentralisedStableCoin private immutable i_dsc;

    mapping(address token => address priceFeeds) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address minter => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    /////////////////////////////////////////////
    ///////////////EVENTS////////////////////////
    /////////////////////////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed reedemedFrom, address indexed to ,uint256 amount, address indexed tokenAddress);

    ///////////////////////////////////////////
    ///////////////MODIFIERS///////////////////
    ///////////////////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MoreThanZero();
        }
        _;
    }

    modifier isAloowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }
    //////////////////////////////////////
    /////////////FUNCTIONS////////////////
    //////////////////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressLengthShouldBeSame();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }
    //////////////////////////////////////
    //////////EXTERNAL FUNCTIONS//////////
    ///////////////////////////////////////

    //@param -->> this function deposits collateral and mints DSC at the same time.

    function depositCollateralAndMintDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 mintAmount)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(mintAmount);
    }

    //@param tokenCollateralAddress: The address of token deposit as collateral
    //@param collateralAmount : The amount of collateral to deposit
    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        isAloowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function reedemCollateralForDSC(address tokenCollateralAddress ,uint256 collateralAmount , uint256 amountDSCToBurn) external {
        burnDSC(amountDSCToBurn);
        reedemCollateral(tokenCollateralAddress, collateralAmount);
    }

    //Healthfactor must be over 1 after collateral pulled
    //DRY : Don't repeat Yourself
    //CEI: Check , Effects , Interactions
    function reedemCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
    {
        _reedemCollateral(msg.sender , msg.sender , tokenCollateralAddress , collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    //1.Check if collateral value is > DSC Amount

    function mintDSC(uint256 amountDSC) public moreThanZero(amountDSC) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSC;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSC);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount){
         
         _burnDSC( amount,msg.sender , msg.sender );
        _revertIfHealthFactorIsBroken(msg.sender);// idn't think it will trigger
    }


    //$100 eth backing $50 DSC
    //Now $20 eth backs -> $50 DSC <- DSC isn't worth $1!!!

    //If someone is almost undercollaterised , we will pay you to liquidate them.

    //@param debtToCover the amount of DSC you want to burn to improve users health factor -->> You can partially liquidate a user and get liquidation bonus
    //@notice This function assumes that protocol will be roughly 200% overcollateralized in order for this to work.

    function liquidate(address collateral , address user , uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor > MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOkay();
        }

        //Bad user : $140 eth , $100 DSC
        //debtToCover : $100
        //$100 DSC == ??? Eth
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral , debtToCover);

        // we want ot give them a 10% bonus

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATOR_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateral = tokenAmountFromDebtCovered + bonusCollateral;
        // We will now reedem this totalCollateralvalue
        _reedemCollateral(user, msg.sender, collateral, totalCollateral);
        //Now we need to burn the DSC
        _burnDSC(debtToCover , user , msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);

        if(endingHealthFactor <= startingUserHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);//to check if the liquidators health factor doesn't falls below.

    }
    function getHealthfactor(address user) external view returns(uint256){
          uint256 healthFactor = _healthFactor(user);

          return healthFactor;
    }

    //////////////////////////////////////////////
    ////////////// PUBLIC FUNCTIONS //////////////
    //////////////////////////////////////////////

    function getTokenAmountFromUsd(address token , uint256 usdAmountInWei) public view returns(uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price ,,,) = pricefeed.latestRoundData();

        // ($10e18 * 1e18)  / ($2000e8 * 1e10)

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
    function getAccountCollateralValue(address user) public view returns (uint256 collateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            collateralValueInUSD += getUSDValue(token, amount);
        }
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /////////////////////////////////////////////////////////
    /////////INTERNAL & PRIVATE VIEW FUNCTIONS///////////////
    /////////////////////////////////////////////////////////

    function _burnDSC(uint256 amountDSCToBurn , address onBehalfOf , address dscFrom) private {
          s_DSCMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(dscFrom , address(this) , amountDSCToBurn);// i_dsc contract me le jaane ke liye we did transfer from from it and we eventually will call the brun function there.
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    function _reedemCollateral( address from , address to ,address tokenCollateralAddress , uint256 collateralAmount ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= collateralAmount;
        emit CollateralRedeemed(from,to, collateralAmount, tokenCollateralAddress);
        bool success = IERC20(tokenCollateralAddress).transfer(to , collateralAmount);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }
    function _getAccountInfo(address user) private view returns (uint256 dscMinted, uint256 collateralValueInUSD) {
        dscMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    //@param -->> Returns how close to liquidation a user is.
    //@param -->> if user gets less than 1, then they get liquidated.
    function _healthFactor(address user) private view returns (uint256) {
        //get account information about DSC minted and collateral value
        (uint256 dscMinted, uint256 collateralValueInUSD) = _getAccountInfo(user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // 1000$ eth / 100DSC
        // 1000*50 = 50000/100 = 500 > 1
        return (collateralAdjustedForThreshold * PRECISION) / dscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1.Check Health Factor & Revert if they don't.
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
        
    }
    function getAccountInformation(address user) external view returns(uint256 totalDSCMinted , uint256 collateralValueInUsd){
        (totalDSCMinted , collateralValueInUsd) = _getAccountInfo(user);
    }
    function getDSCAmountFromUser(address user) external view returns(uint256){
        return s_DSCMinted[user];
    }
    function getLiquidationThreshold() external pure returns(uint256) {
        return LIQUIDATION_THRESHOLD;
    }
    function getLiquidationPrecision() external pure returns(uint256) {
        return LIQUIDATION_PRECISION;
    }
    function getDsc() external view returns(address dsc) {
        return address(i_dsc);
    }
    function getAccountInfo(address user) external view returns(uint256 , uint256){
        return _getAccountInfo(user);
    }
    function getCollateralTokens() external view returns(address[] memory){
        return s_collateralTokens;
    }
    function getCollateralValueOfUser(address user , address token) external view returns(uint256){
        return s_collateralDeposited[user][token];
    }
}
