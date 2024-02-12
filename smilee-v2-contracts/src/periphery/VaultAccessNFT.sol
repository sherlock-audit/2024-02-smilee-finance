// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {IVaultAccessNFT} from "../interfaces/IVaultAccessNFT.sol";

/**
    @title Simple implementation of IVaultAccessNFT

    An example implementation of the priority access tokens for Smilee vaults.
 */
contract VaultAccessNFT is IVaultAccessNFT, ERC721, AccessControl {
    uint256 private _currentId = 0;
    IAddressProvider private immutable _ap;
    mapping(uint256 => uint256) private _priorityDeposit;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    error CallerNotVault();
    error ExceedsAvailable();

    constructor(address addressProvider) ERC721("Smilee Vault Priority Access Token", "SPT") AccessControl() {
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
        @param priorityDeposit The amount `receiver` will be allowed to deposit in Vaults with priority access
        @return tokenId The numerical ID of the minted token
     */
    function createToken(address receiver, uint256 priorityDeposit) public returns (uint tokenId) {
        _checkRole(ROLE_ADMIN);

        tokenId = ++_currentId;
        _priorityDeposit[tokenId] = priorityDeposit;

        _mint(receiver, tokenId);
    }

    /// @inheritdoc IVaultAccessNFT
    function priorityAmount(uint256 tokenId) external view returns (uint256 amount) {
        _requireMinted(tokenId);

        return _priorityDeposit[tokenId];
    }

    /// @inheritdoc IVaultAccessNFT
    function decreasePriorityAmount(uint256 tokenId, uint256 amount) external {
        if (!IRegistry(_ap.registry()).isRegisteredVault(msg.sender)) {
            revert CallerNotVault();
        }

        if (amount > _priorityDeposit[tokenId]) {
            revert ExceedsAvailable();
        }

        _priorityDeposit[tokenId] -= amount;
        if (_priorityDeposit[tokenId] == 0) {
            _burn(tokenId);
        }
    }
}
