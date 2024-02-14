// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Setup} from "./Setup.sol";
import {VaultLib} from "@project/lib/VaultLib.sol";
import {VaultUtils} from "../../utils/VaultUtils.sol";
import {FinanceParameters} from "@project/lib/FinanceIG.sol";
import {TestOptionsFinanceHelper} from "../lib/TestOptionsFinanceHelper.sol";

abstract contract BeforeAfter is Setup {
    uint256 internal _initialStrike;
    uint256 internal _endingStrike;

    VaultLib.VaultState internal _initialVaultState;
    VaultLib.VaultState internal _endingVaultState;

    FinanceParameters internal _initialFinanceParameters;
    FinanceParameters internal _endingFinanceParameters;

    uint256 internal _initialVaultTotalSupply;
    uint256 internal _endingVaultTotalSupply;

    uint256 internal _initialSharePrice;
    uint256 internal _endingSharePrice;

    function _before() internal {
        (_endingStrike, _endingVaultState, _endingFinanceParameters, _endingVaultTotalSupply, _endingSharePrice) = _collectData();
    }

    function _after() internal {
        (_initialStrike, _initialVaultState, _initialFinanceParameters, _initialVaultTotalSupply, _initialSharePrice) = _collectData();
    }

    function _collectData()
        internal view
        returns (
            uint256 currentStrike,
            VaultLib.VaultState memory vaultState,
            FinanceParameters  memory financeParameters,
            uint256 vaultTotalSupply,
            uint256 sharePrice
        )
    {
        currentStrike = ig.currentStrike();
        vaultState = VaultUtils.vaultState(vault);
        financeParameters = TestOptionsFinanceHelper.getFinanceParameters(ig);
        vaultTotalSupply = vault.totalSupply();
        sharePrice = vault.epochPricePerShare(ig.getEpoch().previous);
    }
}
