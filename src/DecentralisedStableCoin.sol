// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title Decentralised Stable Coin
/// @author BlockBuddy
/// @notice Makes a dcentralised token or a stbale coin
/*
*
*  This contract is governend by DSCEngine.sol
*
*/
contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DSCCoin__MustBeMoreThanZero();
    error DSCCoin__BurnExceedsBalance();
    error DSCCoin__ZeroAddress();

    constructor() ERC20("BlockBuddy", "BDY") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DSCCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DSCCoin__BurnExceedsBalance();
        }
        super.burn(_amount); //it tells that go to thr main class of main contract to use the burn function
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DSCCoin__ZeroAddress();
        }
        if (_amount <= 0) {
            revert DSCCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
