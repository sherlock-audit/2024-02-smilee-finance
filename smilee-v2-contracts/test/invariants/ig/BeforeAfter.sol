// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "../system/Setup.sol";

abstract contract BeforeAfter is Setup {
  struct Vars {
    uint256 value;
  }

  Vars internal _before;
  Vars internal _after;

  function __before() internal {
  }

  function __after() internal {
  }
}
