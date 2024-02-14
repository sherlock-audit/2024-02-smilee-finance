// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {TargetFunctions} from "../system/TargetFunctions.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";

contract CryticTester is TargetFunctions, CryticAsserts {

    address internal depositor = address(0xf9a);

    constructor() {
        setup();

        VaultUtils.addVaultDeposit(depositor, INITIAL_VAULT_DEPOSIT, admin, address(vault), _convertVm());
        skipDay(false);
        hevm.prank(admin);
        ig.rollEpoch();
    }
}
