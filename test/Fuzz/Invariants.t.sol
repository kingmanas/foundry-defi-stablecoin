// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// what are our invariants?

//1. Total DSC should be less than total value of collateral.
//2. getter view functions should never revert <- evergreen invariant

import {Test , console} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant , Test {

    DeployDSC deployer;
    DSCEngine engine;
    DecentralisedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;
    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,,weth,wbtc,) = config.activeNetworkConfig();
        // targetContract(address(engine));
        handler = new Handler(engine , dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view{
         uint256 totalSupply = dsc.totalSupply();//asses the total supply of the DSC token
         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
         uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(engine));

         uint256 wethValue = engine.getUSDValue(weth, totalWethDeposited);
         uint256 wbtcValue = engine.getUSDValue(wbtc, totalBtcDeposited);
         
         console.log("weth :" , wethValue);
         console.log("wbtc :" , wbtcValue);
         console.log("totalSupply :" , totalSupply);
         console.log("TimesMintCalled :" , handler.timesMintCalled());
         assert(wethValue + wbtcValue >= totalSupply);
         
    }
    function invariant_getterShouldNotRevert() public view {
        engine.getDsc();
        engine.getLiquidationPrecision();
    }
}
