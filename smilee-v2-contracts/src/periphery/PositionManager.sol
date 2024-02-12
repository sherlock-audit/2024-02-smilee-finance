// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDVP} from "../interfaces/IDVP.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";
import {Position} from "../lib/Position.sol";
import {Epoch} from "../lib/EpochController.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PositionManager is ERC721Enumerable, Ownable, IPositionManager {
    using SafeERC20 for IERC20;

    struct ManagedPosition {
        address dvpAddr;
        uint256 strike;
        uint256 expiry;
        uint256 notionalUp;
        uint256 notionalDown;
        uint256 premium;
        uint256 leverage;
        uint256 cumulatedPayoff;
    }

    /// @dev Stored data by position ID
    mapping(uint256 => ManagedPosition) internal _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 private _nextId;

    // Used by TheGraph for frontend needs:
    event Buy(address dvp, uint256 epoch, uint256 premium, address creditor);
    event Sell(address dvp, uint256 epoch, uint256 payoff);

    error CantBurnMoreThanMinted();
    error InvalidTokenID();
    error NotOwner();
    error PositionExpired();
    error AsymmetricAmount();

    constructor() ERC721Enumerable() ERC721("Smilee V0 Trade Positions", "SMIL-V0-TRAD") Ownable() {
        _nextId = 1;
    }

    modifier isOwner(uint256 tokenId) {
        if (ownerOf(tokenId) != msg.sender) {
            revert NotOwner();
        }
        _;
    }

    // modifier isAuthorizedForToken(uint256 tokenId) {
    //     if (!_isApprovedOrOwner(msg.sender, tokenId)) {
    //         revert NotApproved();
    //     }
    //     _;
    // }

    /// @inheritdoc IPositionManager
    function positionDetail(uint256 tokenId) external view override returns (IPositionManager.PositionDetail memory) {
        ManagedPosition memory position = _positions[tokenId];
        if (position.dvpAddr == address(0)) {
            revert InvalidTokenID();
        }

        IDVP dvp = IDVP(position.dvpAddr);

        Epoch memory epoch = dvp.getEpoch();

        return
            IPositionManager.PositionDetail({
                dvpAddr: position.dvpAddr,
                baseToken: dvp.baseToken(),
                sideToken: dvp.sideToken(),
                dvpFreq: epoch.frequency,
                dvpType: dvp.optionType(),
                strike: position.strike,
                expiry: position.expiry,
                premium: position.premium,
                leverage: position.leverage,
                notionalUp: position.notionalUp,
                notionalDown: position.notionalDown,
                cumulatedPayoff: position.cumulatedPayoff
            });
    }

    /// @inheritdoc IPositionManager
    function mint(
        IPositionManager.MintParams calldata params
    ) external override returns (uint256 tokenId, uint256 premium) {
        IDVP dvp = IDVP(params.dvpAddr);

        if (params.tokenId != 0) {
            tokenId = params.tokenId;
            ManagedPosition storage position = _positions[tokenId];

            if (ownerOf(tokenId) != msg.sender) {
                revert NotOwner();
            }
            // Check token compatibility:
            if (position.dvpAddr != params.dvpAddr || position.strike != params.strike) {
                revert InvalidTokenID();
            }
            Epoch memory epoch = dvp.getEpoch();
            if (position.expiry != epoch.current) {
                revert PositionExpired();
            }
        }
        if ((params.notionalUp > 0 && params.notionalDown > 0) && (params.notionalUp != params.notionalDown)) {
            // If amount is a smile, it must be balanced:
            revert AsymmetricAmount();
        }

        uint256 obtainedPremium;
        uint256 fee;
        (obtainedPremium, fee) = dvp.premium(params.strike, params.notionalUp, params.notionalDown);

        // Transfer premium:
        // NOTE: The PositionManager is just a middleman between the user and the DVP
        IERC20 baseToken = IERC20(dvp.baseToken());
        baseToken.safeTransferFrom(msg.sender, address(this), obtainedPremium);

        // Premium already include fee
        baseToken.safeApprove(params.dvpAddr, obtainedPremium);

        premium = dvp.mint(
            address(this),
            params.strike,
            params.notionalUp,
            params.notionalDown,
            params.expectedPremium,
            params.maxSlippage,
            params.nftAccessTokenId
        );

        if (obtainedPremium > premium) {
            baseToken.safeTransferFrom(address(this), msg.sender, obtainedPremium - premium);
        }

        if (params.tokenId == 0) {
            // Mint token:
            tokenId = _nextId++;
            _mint(params.recipient, tokenId);

            Epoch memory epoch = dvp.getEpoch();

            // Save position:
            _positions[tokenId] = ManagedPosition({
                dvpAddr: params.dvpAddr,
                strike: params.strike,
                expiry: epoch.current,
                premium: premium,
                leverage: (params.notionalUp + params.notionalDown) / premium,
                notionalUp: params.notionalUp,
                notionalDown: params.notionalDown,
                cumulatedPayoff: 0
            });
        } else {
            ManagedPosition storage position = _positions[tokenId];
            // Increase position:
            position.premium += premium;
            position.notionalUp += params.notionalUp;
            position.notionalDown += params.notionalDown;
            /* NOTE:
                When, within the same epoch, a user wants to buy, sell partially
                and then buy again, the leverage computation can fail due to
                decreased notional; in order to avoid this issue, we have to
                also adjust (decrease) the premium in the burn flow.
             */
            position.leverage = (position.notionalUp + position.notionalDown) / position.premium;
        }

        emit BuyDVP(tokenId, _positions[tokenId].expiry, params.notionalUp + params.notionalDown);
        emit Buy(params.dvpAddr, _positions[tokenId].expiry, premium, params.recipient);
    }

    function payoff(
        uint256 tokenId,
        uint256 notionalUp,
        uint256 notionalDown
    ) external view returns (uint256 payoff_, uint256 fee) {
        ManagedPosition storage position = _positions[tokenId];
        return IDVP(position.dvpAddr).payoff(position.expiry, position.strike, notionalUp, notionalDown);
    }

    function sell(SellParams calldata params) external isOwner(params.tokenId) returns (uint256 payoff_) {
        payoff_ = _sell(
            params.tokenId,
            params.notionalUp,
            params.notionalDown,
            params.expectedMarketValue,
            params.maxSlippage
        );
    }

    function sellAll(SellParams[] calldata params) external returns (uint256 totalPayoff_) {
        uint256 paramsLength = params.length;
        for (uint256 i = 0; i < paramsLength; i++) {
            if (ownerOf(params[i].tokenId) != msg.sender) {
                revert NotOwner();
            }
            totalPayoff_ += _sell(
                params[i].tokenId,
                params[i].notionalUp,
                params[i].notionalDown,
                params[i].expectedMarketValue,
                params[i].maxSlippage
            );
        }
    }

    function _sell(
        uint256 tokenId,
        uint256 notionalUp,
        uint256 notionalDown,
        uint256 expectedMarketValue,
        uint256 maxSlippage
    ) internal returns (uint256 payoff_) {
        ManagedPosition storage position = _positions[tokenId];
        // NOTE: as the positions within the DVP are all of the PositionManager, we must replicate this check here.
        if (notionalUp > position.notionalUp || notionalDown > position.notionalDown) {
            revert CantBurnMoreThanMinted();
        }

        if ((notionalUp > 0 && notionalDown > 0) && (notionalUp != notionalDown)) {
            // If amount is a smile, it must be balanced:
            revert AsymmetricAmount();
        }

        // NOTE: the DVP already checks that the burned notional is lesser or equal to the position notional.
        // NOTE: the payoff is transferred directly from the DVP
        payoff_ = IDVP(position.dvpAddr).burn(
            position.expiry,
            msg.sender,
            position.strike,
            notionalUp,
            notionalDown,
            expectedMarketValue,
            maxSlippage
        );

        // NOTE: premium fix for the leverage issue annotated in the mint flow.
        // notional : position.notional = fix : position.premium
        uint256 premiumFix = ((notionalUp + notionalDown) * position.premium) /
            (position.notionalUp + position.notionalDown);
        position.premium -= premiumFix;
        position.cumulatedPayoff += payoff_;
        position.notionalUp -= notionalUp;
        position.notionalDown -= notionalDown;

        if (position.notionalUp == 0 && position.notionalDown == 0) {
            delete _positions[tokenId];
            _burn(tokenId);
        }

        emit SellDVP(tokenId, (notionalUp + notionalDown), payoff_);
        emit Sell(position.dvpAddr, position.expiry, payoff_);
    }
}
