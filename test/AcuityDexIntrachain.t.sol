// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AcuityDexIntrachain} from "../src/AcuityDexIntrachain.sol";

contract AcuityDexIntrachainTest is Test {
    AcuityDexIntrachain public dex;

    function setUp() public {
        dex = new AcuityDexIntrachain();
    }

    function testStub() public {
        assert(true);
    }

}
