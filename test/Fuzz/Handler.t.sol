// we are goonnna narrow down the way we call functions.

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "lib/forge-std/src/Test.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralisedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintCalled;
    address[] public userWithCollateralDeposited;

    uint256 MAX_DEPOSIT_AMOUNT = type(uint96).max;// we did uint96 so that we cannot pass the upper limit of uint256
    constructor(DSCEngine _engine , DecentralisedStableCoin _dsc ) {
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function mintDSC(uint256 amount , uint256 addressSeed) public {// we have to use the addresses who have depositedollateral.
        if(userWithCollateralDeposited.length == 0){
            return;
        }
        address sender = userWithCollateralDeposited[addressSeed % userWithCollateralDeposited.length]; 
        (uint256 dscMinted, uint256 collateralValueInUSD) = engine.getAccountInfo(msg.sender);
        int256 maxMintValue = (int256(collateralValueInUSD)/2) - int256(dscMinted);
         
        if(maxMintValue<0){
           return;
        }
        
        amount = bound (amount , 0 , uint256(maxMintValue));
        if(amount==0){
            return;
        }
        vm.startPrank(sender);
        engine.mintDSC(amount);
        vm.stopPrank();
        timesMintCalled++;
       
    }
    function mintAndDepositCollateral(uint256 collateralSeed , uint256 amountCollateral) public {//Bina mint kiye collateral deposit karoge kaise meremunna
        //  engine.depositCollateral(collateral, amountCollateral);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);// we used ERC20Mock to mint the tokens
        amountCollateral = bound(amountCollateral , 1 , MAX_DEPOSIT_AMOUNT);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender , amountCollateral);
        //we have to approve it
        collateral.approve(address(engine) , amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userWithCollateralDeposited.push(msg.sender);
    } 

    //Helper functions-->>

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed % 2 ==0){
            return weth;
        }else{
            return wbtc;
        }
    }

    function reedemCollateral(uint256 collateralSeed , uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        /// a person can only reedem the amount of collateral present in the system.
        uint256 maxCollateral = engine.getCollateralValueOfUser(address(collateral) , msg.sender);
        amountCollateral = bound(amountCollateral , 0 ,maxCollateral);
        if(amountCollateral == 0){// so that if maxCollateral is zero it returns.
            return;
        }
        engine.reedemCollateral(address(collateral), amountCollateral);
    }
}