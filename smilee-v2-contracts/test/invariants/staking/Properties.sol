// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";

abstract contract Properties is Setup {
  // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);

    string internal constant STK_1 = "STK_1: Expected reward supply";
    string internal constant STK_2 = "STK_2: Expected pending reward";
    string internal constant STK_3 = "STK_3: Expected reward";
    string internal constant STK_4 = "STK_4: Expected staker final share balance";

}
