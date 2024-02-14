// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {TargetFunctions} from "./TargetFunctions.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";

contract CryticTester is TargetFunctions, CryticAsserts {
    constructor() {
        setup();
    }
}
