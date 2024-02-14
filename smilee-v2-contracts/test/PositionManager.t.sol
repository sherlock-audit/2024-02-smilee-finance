// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ud, convert} from "@prb/math/UD60x18.sol";
import {IPositionManager} from "@project/interfaces/IPositionManager.sol";
import {EpochFrequency} from "@project/lib/EpochFrequency.sol";
import {OptionStrategy} from "@project/lib/OptionStrategy.sol";
import {Epoch} from "@project/lib/EpochController.sol";
import {Utils} from "./utils/Utils.sol";
import {VaultUtils} from "./utils/VaultUtils.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {AddressProvider} from "@project/AddressProvider.sol";
import {FeeManager} from "@project/FeeManager.sol";
import {MarketOracle} from "@project/MarketOracle.sol";
import {IG} from "@project/IG.sol";
import {PositionManager} from "@project/periphery/PositionManager.sol";
import {TestnetPriceOracle} from "@project/testnet/TestnetPriceOracle.sol";
import {MockedVault} from "./mock/MockedVault.sol";
import {MockedRegistry} from "./mock/MockedRegistry.sol";

contract PositionManagerTest is Test {
    bytes4 constant NotOwner = bytes4(keccak256("NotOwner()"));
    bytes4 constant AmountZero = bytes4(keccak256("AmountZero()"));
    bytes4 constant InvalidTokenID = bytes4(keccak256("InvalidTokenID()"));
    bytes4 constant CantBurnMoreThanMinted = bytes4(keccak256("CantBurnMoreThanMinted()"));
    bytes4 constant SlippedMarketValue = bytes4(keccak256("SlippedMarketValue()"));

    address baseToken;
    address sideToken;

    MockedVault vault;

    address admin = address(0x10);
    address alice = address(0x1);
    address bob = address(0x2);

    IPositionManager pm;
    MockedRegistry registry;
    AddressProvider ap;
    FeeManager feeManager;

    constructor() {
        vm.warp(EpochFrequency.REF_TS + 1);

        vm.prank(admin);
        ap = new AddressProvider(0);

        vault = MockedVault(VaultUtils.createVault(EpochFrequency.DAILY, ap, admin, vm));
        baseToken = vault.baseToken();
        sideToken = vault.sideToken();

        registry = MockedRegistry(ap.registry());
        feeManager = FeeManager(ap.feeManager());
    }

    function setUp() public {
        pm = new PositionManager();

        // NOTE: done in order to work with the limited transferability of the testnet tokens
        vm.prank(admin);
        ap.setDvpPositionManager(address(pm));

        // Suppose Vault has already liquidity
        VaultUtils.addVaultDeposit(alice, 100 ether, admin, address(vault), vm);
    }

    function initAndMint() private returns (uint256 tokenId, IG ig) {
        vm.startPrank(admin);
        ig = new IG(address(vault), address(ap));
        ig.grantRole(ig.ROLE_ADMIN(), admin);
        ig.grantRole(ig.ROLE_EPOCH_ROLLER(), admin);
        vault.grantRole(vault.ROLE_ADMIN(), admin);
        vault.setAllowedDVP(address(ig));

        MarketOracle mo = MarketOracle(ap.marketOracle());

        mo.setDelay(ig.baseToken(), ig.sideToken(), ig.getEpoch().frequency, 0, true);

        Utils.skipDay(true, vm);
        ig.rollEpoch();
        vm.stopPrank();

        uint256 strike = ig.currentStrike();

        (uint256 expectedMarketValue, ) = ig.premium(0, 10 ether, 0);
        TokenUtils.provideApprovedTokens(admin, baseToken, DEFAULT_SENDER, address(pm), expectedMarketValue, vm);
        // NOTE: somehow, the sender is something else without this prank...
        vm.prank(DEFAULT_SENDER);
        (tokenId, ) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: strike,
                recipient: alice,
                tokenId: 0,
                expectedPremium: expectedMarketValue,
                maxSlippage: 0.1e18,
                nftAccessTokenId: 0
            })
        );
        assertGe(1, tokenId);
        assertGe(1, pm.totalSupply());
    }

    function testMint() public {
        (uint256 tokenId, IG ig) = initAndMint();

        assertEq(1, tokenId);

        IPositionManager.PositionDetail memory pos = pm.positionDetail(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(false, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        Epoch memory epoch = ig.getEpoch();
        assertEq(epoch.current, pos.expiry);
        assertEq(10 ether, pos.notionalUp);
        assertEq(0, pos.notionalDown);
        // assertEq(10, pos.leverage);
        // assertEq(1 ether, pos.premium);
        assertEq(0, pos.cumulatedPayoff);
    }

    function testCantBurnZero() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        vm.expectRevert(AmountZero);
        pm.sell(
            IPositionManager.SellParams({
                tokenId: tokenId,
                notionalUp: 0,
                notionalDown: 0,
                expectedMarketValue: 0,
                maxSlippage: 0.1e18
            })
        );
    }

    function testCantBurnTooMuch() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        vm.expectRevert(CantBurnMoreThanMinted);
        pm.sell(
            IPositionManager.SellParams({
                tokenId: tokenId,
                notionalUp: 11 ether,
                notionalDown: 0,
                expectedMarketValue: 0,
                maxSlippage: 0.1e18
            })
        );
    }

    function testMintAndBurn() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        pm.sell(
            IPositionManager.SellParams({
                tokenId: tokenId,
                notionalUp: 10 ether,
                notionalDown: 0,
                expectedMarketValue: 0,
                maxSlippage: 0.1e18
            })
        );

        vm.expectRevert(InvalidTokenID);
        pm.positionDetail(tokenId);
    }

    function testMintAndBurnAll() public {
        (uint256 tokenId, ) = initAndMint();

        vm.prank(alice);
        IPositionManager.SellParams[] memory sellParams = new IPositionManager.SellParams[](1);
        sellParams[0] = IPositionManager.SellParams({
            tokenId: tokenId,
            notionalUp: 10 ether,
            notionalDown: 0,
            expectedMarketValue: 0,
            maxSlippage: 0.1e18
        });
        pm.sellAll(sellParams);

        vm.expectRevert(InvalidTokenID);
        pm.positionDetail(tokenId);
    }

    function testMintTwiceSamePosition() public {
        (uint256 tokenId, IG ig) = initAndMint();

        assertEq(1, tokenId);

        IPositionManager.PositionDetail memory pos = pm.positionDetail(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(false, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        Epoch memory epoch = ig.getEpoch();
        assertEq(epoch.current, pos.expiry);
        assertEq(10 ether, pos.notionalUp);
        assertEq(0, pos.notionalDown);
        assertEq(0, pos.cumulatedPayoff);

        TokenUtils.provideApprovedTokens(admin, baseToken, alice, address(pm), 10 ether, vm);

        uint256 strike = ig.currentStrike();

        (uint256 expectedMarketValue, ) = ig.premium(strike, 10 ether, 0);

        vm.prank(alice);

        (tokenId, ) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: strike,
                recipient: alice,
                tokenId: 1,
                expectedPremium: expectedMarketValue,
                maxSlippage: 0.1e18,
                nftAccessTokenId: 0
            })
        );

        pos = pm.positionDetail(tokenId);

        assertEq(address(ig), pos.dvpAddr);
        assertEq(baseToken, pos.baseToken);
        assertEq(sideToken, pos.sideToken);
        assertEq(EpochFrequency.DAILY, pos.dvpFreq);
        assertEq(false, pos.dvpType);
        assertEq(ig.currentStrike(), pos.strike);
        epoch = ig.getEpoch();
        assertEq(epoch.current, pos.expiry);
        assertEq(20 ether, pos.notionalUp);
        assertEq(0, pos.notionalDown);
        assertEq(0, pos.cumulatedPayoff);
    }

    function testMintPositionNotOwner() public {
        (uint256 tokenId, IG ig) = initAndMint();

        TokenUtils.provideApprovedTokens(admin, baseToken, address(0x5), address(pm), 10 ether, vm);

        uint256 strike = ig.currentStrike();
        vm.prank(address(0x5));
        vm.expectRevert(NotOwner);
        (tokenId, ) = pm.mint(
            IPositionManager.MintParams({
                dvpAddr: address(ig),
                notionalUp: 10 ether,
                notionalDown: 0,
                strike: strike,
                recipient: address(0x5),
                tokenId: 1,
                expectedPremium: 0,
                maxSlippage: 0.1e18,
                nftAccessTokenId: 0
            })
        );
    }

    // function testSlippage() public {
    //     (, IG ig) = initAndMint();

    //     uint256 strike = ig.currentStrike();
    //     (uint256 expectedMarketValue, ) = ig.premium(0, 10 ether, 0);
    //     uint256 slippage = ud(expectedMarketValue).mul(ud(0.1e18)).unwrap();

    //     TokenUtils.provideApprovedTokens(
    //         admin,
    //         baseToken,
    //         DEFAULT_SENDER,
    //         address(pm),
    //         expectedMarketValue + slippage,
    //         vm
    //     );

    //     TestnetPriceOracle po = TestnetPriceOracle(ap.priceOracle());

    //     vm.startPrank(admin);
    //     // Increase the premium of about 9.8% and anyway below the slippage value of 10%
    //     po.setTokenPrice(ig.sideToken(), 1.0014e18);
    //     vm.stopPrank();

    //     (uint256 expectedMarketValue2, ) = ig.premium(0, 10e18, 0);
    //     assertLt(expectedMarketValue2, expectedMarketValue + slippage);

    //     // Pass because 9.8% is less than 10% (slippage)
    //     vm.prank(DEFAULT_SENDER);
    //     pm.mint(
    //         IPositionManager.MintParams({
    //             dvpAddr: address(ig),
    //             notionalUp: 10 ether,
    //             notionalDown: 0,
    //             strike: strike,
    //             recipient: address(0x5),
    //             tokenId: 0,
    //             expectedPremium: expectedMarketValue,
    //             maxSlippage: 0.1e18,
    //             nftAccessTokenId: 0
    //         })
    //     );

    //     // Increase premium of about 18% which is higher than 10% (slippage)
    //     vm.startPrank(admin);
    //     po.setTokenPrice(ig.sideToken(), 1.002 ether);
    //     vm.stopPrank();

    //     /**
    //      * Approve the preview premium with slippage
    //      */
    //     TokenUtils.provideApprovedTokens(
    //         admin,
    //         baseToken,
    //         DEFAULT_SENDER,
    //         address(pm),
    //         expectedMarketValue + slippage,
    //         vm
    //     );

    //     (uint256 expectedMarketValue3, ) = ig.premium(0, 10e18, 0);
    //     console.log(expectedMarketValue3);
    //     assertGt(expectedMarketValue3, expectedMarketValue + slippage);

    //     vm.prank(DEFAULT_SENDER);
    //     vm.expectRevert("ERC20: insufficient allowance");
    //     pm.mint(
    //         IPositionManager.MintParams({
    //             dvpAddr: address(ig),
    //             notionalUp: 10 ether,
    //             notionalDown: 0,
    //             strike: strike,
    //             recipient: address(0x5),
    //             tokenId: 0,
    //             expectedPremium: expectedMarketValue,
    //             maxSlippage: 0.1e18,
    //             nftAccessTokenId: 0
    //         })
    //     );

    //     /**
    //      * Approve all the balance of the user or anyway greather than the expected value + slippage
    //      */
    //     TokenUtils.provideApprovedTokens(admin, baseToken, DEFAULT_SENDER, address(pm), 100e18, vm);
    //     vm.prank(DEFAULT_SENDER);
    //     vm.expectRevert(SlippedMarketValue);
    //     pm.mint(
    //         IPositionManager.MintParams({
    //             dvpAddr: address(ig),
    //             notionalUp: 10 ether,
    //             notionalDown: 0,
    //             strike: strike,
    //             recipient: address(0x5),
    //             tokenId: 0,
    //             expectedPremium: expectedMarketValue,
    //             maxSlippage: 0.1e18,
    //             nftAccessTokenId: 0
    //         })
    //     );
    // }
}
