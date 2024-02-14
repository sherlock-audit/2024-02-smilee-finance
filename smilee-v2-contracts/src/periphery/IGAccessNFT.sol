// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {IDVPAccessNFT} from "../interfaces/IDVPAccessNFT.sol";

/**
    @title Simple implementation of IDVPAccessNFT

    An example implementation of the priority access tokens for Smilee vaults.
 */
contract IGAccessNFT is IDVPAccessNFT, ERC721, AccessControl {
    uint256 private _currentId = 0;
    IAddressProvider private immutable _ap;
    mapping(uint256 => uint256) private _capAmount;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    error NotionalCapExceeded();

    constructor(address addressProvider) ERC721("Smilee Trade Priority Access Token", "STPT") AccessControl() {
        _ap = IAddressProvider(addressProvider);

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC721, IERC165) returns (bool) {
        return ERC721.supportsInterface(interfaceId) && AccessControl.supportsInterface(interfaceId);
    }

    /**
        @notice Creates a token
        @param receiver The accounting wallet for this token
        @param capAmount_ The amount of notional `receiver` will be allowed to trade in DVP.
        @return tokenId The numerical ID of the minted token
     */
    function createToken(address receiver, uint256 capAmount_) public returns (uint tokenId) {
        _checkRole(ROLE_ADMIN);

        tokenId = ++_currentId;
        _capAmount[tokenId] = capAmount_;

        _mint(receiver, tokenId);
    }

    /// @inheritdoc IDVPAccessNFT
    function capAmount(uint256 tokenId) external view returns (uint256 amount) {
        _requireMinted(tokenId);

        return _capAmount[tokenId];
    }

    function checkCap(uint256 tokenId, uint256 amount) external view {
        if(amount > _capAmount[tokenId]) {
            revert NotionalCapExceeded();
        }
    }
}
