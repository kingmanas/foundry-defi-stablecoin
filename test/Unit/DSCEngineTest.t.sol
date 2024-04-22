// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test , console} from "lib/forge-std/src/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";

contract DSCEngineTest is Test {
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ETHER_BALANCE = 20 ether;
    uint256 public constant AMOUNT_TOKENS_MINT = 5 ether;

    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();

        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        

        ERC20Mock(weth).mint(USER, STARTING_ETHER_BALANCE);
        // ERC20Mock(wbtc).mint(USER, STARTING_ETHER_BALANCE);
    }
    
    ///////////////////////////
    //////CONSTRUCTOR TESTS////
    ///////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedsAddresses;

    function testRevertsIfDoesntMatchPriceFeeds() public {
       tokenAddresses.push(weth);
       priceFeedsAddresses.push(ethUsdPriceFeed);
       priceFeedsAddresses.push(btcUsdPriceFeed);

       vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressLengthShouldBeSame.selector);
       
       new DSCEngine(tokenAddresses , priceFeedsAddresses ,address(dsc));
    }



    ///////////////////////////
    //////PRICE TESTS//////////
    ///////////////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;

        uint256 realUsd = engine.getUSDValue(weth, ethAmount);
        assertEq(expectedUsd, realUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth , usdAmount);
        assertEq(actualWeth , expectedWeth);
    }

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert();
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfLessThanZeroCollateralDeposited() public {
        tokenAddresses.push(weth);
        uint256 amount = 0 ether;
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.depositCollateral(weth , amount);

    }
    modifier depositedCollateral(){// it approves a certain amount (AMOUNT_COLLATERAL) of a mock ERC20 token (weth) for spending by the DSCEngine contract.
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
    function testCanDepositCollateralAndAccountInfo() public depositedCollateral{
        ( uint256 totalDSCMinted , uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
         uint256 expectedTotalDSCMinted = 0;// we haven't called the mint function so no coins should be minted
         uint256 expectedDepositedCollateral = engine.getTokenAmountFromUsd(weth, collateralValueInUsd); // we are using collateral value in us dto te to the deposited collateral value 

         assertEq(totalDSCMinted , expectedTotalDSCMinted);
         assertEq(AMOUNT_COLLATERAL , expectedDepositedCollateral);
    }

    //TODO
    ///////////////////////////
    ////////MINT TESTS/////////
    ///////////////////////////
    function testCantMintDscIfAmountIsLessThanZero() public {
          vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
          engine.mintDSC(0);// it went instead of depositing collateral coz we have zero collatersl and we are minting zero.
    }

    function testsDSCGetsUpdatedAfterMinting() public depositedCollateral{// we have to deposit collateral first to mint dsc
          uint256 expectedMintDSC = 5 ether;
          vm.startPrank(USER);
          engine.mintDSC(AMOUNT_TOKENS_MINT);
          assertEq( expectedMintDSC, engine.getDSCAmountFromUser(USER));
    }

    function testGetLiquidationPrecision() public view{
        uint256 expectedPrecision = 100;
        uint256 precision = engine.getLiquidationPrecision();
        assertEq(precision , expectedPrecision);
    }
    function testGetLiquidationThreshold() public view{
        uint256 expectedPrecision = 50;
        uint256 precision = engine.getLiquidationThreshold();
        assertEq(precision , expectedPrecision);
    }
    function testGetDsc() public view{
        address idsc = engine.getDsc();
        assertEq(idsc , address(dsc));
    }

    function testGetAcountCollateralValue() public depositedCollateral(){
       
        uint256 expectedValue = engine.getUSDValue(weth, AMOUNT_COLLATERAL);
        uint256 realValue = engine.getAccountCollateralValue(USER);
        assertEq(expectedValue , realValue);
    } 

    function testTokenAmountFromUsd() public depositedCollateral {
      ( , uint256 collateralValue) = engine.getAccountInfo(USER);
      uint256 expectedValue = engine.getUSDValue(weth, AMOUNT_COLLATERAL);
      assertEq(collateralValue , expectedValue);
    }


    // function testIfHealthFactorIsBrokenAfterMinting() public depositedCollateral {
    //       vm.startPrank(USER);
         
    //       vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
    //        engine.mintDSC(AMOUNT_TOKENS_MINT);
    //       console.log(engine.getHealthfactor(USER));
    // }
    // //2000,000000000000000000
}
