// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {VaultLib} from "@project/lib/VaultLib.sol";

contract VaultLibTest is Test {

    function testPricePerShare() public {
        // When there are no shares, the price is defined on a 1:1 ratio, regardless of the assets
        uint256 price = VaultLib.pricePerShare(0, 0, 0);
        assertEq(1e0, price);
        price = VaultLib.pricePerShare(1000e7, 0, 7);
        assertEq(1e7, price);

        // Zero assets gave a zero price, regardless of the shares
        price = VaultLib.pricePerShare(0, 1, 7);
        assertEq(0, price);

        // Otherwise, the price is a ratio of assets over shares
        price = VaultLib.pricePerShare(1e7, 1e7, 7);
        assertEq(1e7, price);
        price = VaultLib.pricePerShare(2e7, 1e7, 7);
        assertEq(2e7, price);
        price = VaultLib.pricePerShare(1e7, 2e7, 7);
        assertEq(0.5e7, price);
    }

    function testAssetToShares() public {
        uint256 shares = VaultLib.assetToShares(0, 0, 0);
        assertEq(0, shares);
        shares = VaultLib.assetToShares(0, 0, 1);
        assertEq(0, shares);
        shares = VaultLib.assetToShares(0, 1, 0);
        assertEq(0, shares);
        shares = VaultLib.assetToShares(1, 0, 0);
        assertEq(0, shares);

        // Check the shares when the price is the one for a 1:1 ratio.
        // NOTE: on a 1:1 ratio, the share price is the unit in terms of decimals.
        shares = VaultLib.assetToShares(1, 1e0, 0);
        assertEq(1e0, shares);
        shares = VaultLib.assetToShares(1, 1e1, 1);
        assertEq(0.1e1, shares);
        shares = VaultLib.assetToShares(1e1, 1e1, 1);
        assertEq(1e1, shares);

        // If the share price drops, we expect more shares:
        shares = VaultLib.assetToShares(1e1, 0.5e1, 1);
        assertEq(2e1, shares);

        // If the share price rise, we expect fewer shares:
        shares = VaultLib.assetToShares(1e1, 2e1, 1);
        assertEq(0.5e1, shares);
    }

    function testSharesToAsset() public {
        uint256 assets = VaultLib.sharesToAsset(0, 0, 0);
        assertEq(0, assets);
        assets = VaultLib.sharesToAsset(1, 0, 0);
        assertEq(0, assets);
        assets = VaultLib.sharesToAsset(0, 1, 0);
        assertEq(0, assets);
        assets = VaultLib.sharesToAsset(0, 0, 1);
        assertEq(0, assets);

        // Check assets when the price is the one for a 1:1 ratio.
        assets = VaultLib.sharesToAsset(1e0, 1e0, 0);
        assertEq(1e0, assets);
        assets = VaultLib.sharesToAsset(1e7, 1e7, 7);
        assertEq(1e7, assets);

        // If the share price drops, we expect fewer assets:
        assets = VaultLib.sharesToAsset(10e7, 0.5e7, 7);
        assertEq(5e7, assets);

        // If the share price rise, we expect more assets:
        assets = VaultLib.sharesToAsset(10e7, 2e7, 7);
        assertEq(20e7, assets);
    }
}
