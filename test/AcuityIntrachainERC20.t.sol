// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {AcuityIntrachainERC20} from "../src/AcuityIntrachainERC20.sol";

contract AcuityIntrachainERC20Test is Test {
    AcuityIntrachainERC20 public intrachainERC20;

    function setUp() public {
        intrachainERC20 = new AcuityIntrachainERC20();
    }
}
