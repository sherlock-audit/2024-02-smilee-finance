// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
    @notice Token contract to be used under testnet condition.
    @dev Transfer is blocked between wallets and only allowed from wallets to
         Liquidity Vaults and DVPs and viceversa. A swapper contract is to mint
         and burn tokens to simulate an exchange.
 */
contract TestnetToken is ERC20, Ownable {

    bool _transferRestricted;
    uint8 private _decimals;
    IAddressProvider private _addressProvider;

    error NotInitialized();
    error Unauthorized();

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable() {
        _transferRestricted = true;
        _decimals = 18;
    }

    /// @inheritdoc ERC20
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 decimals_) external onlyOwner() {
        _decimals = decimals_;
    }

    /// MODIFIERS ///

    modifier initialized() {
        if (address(_addressProvider) == address(0)) {
            revert NotInitialized();
        }
        _;
    }

    modifier checkMintBurnRestriction() {
        if (msg.sender != owner() && msg.sender != _addressProvider.exchangeAdapter()) {
            revert Unauthorized();
        }
        _;
    }

    modifier checkTransferRestriction(address from, address to) {
        IRegistry registry = IRegistry(_addressProvider.registry());
        if (
            _transferRestricted &&
            (msg.sender != owner() &&
                !registry.isRegistered(from) &&
                !registry.isRegistered(to) &&
                _addressProvider.exchangeAdapter() != from &&
                _addressProvider.exchangeAdapter() != to &&
                _addressProvider.dvpPositionManager() != from &&
                _addressProvider.dvpPositionManager() != to &&
                _addressProvider.feeManager() != from &&
                _addressProvider.feeManager() != to &&
                _addressProvider.vaultProxy() != from &&
                _addressProvider.vaultProxy() != to &&
                !registry.isRegisteredVault(from) &&
                !registry.isRegisteredVault(to))
        ) {
            revert Unauthorized();
        }
        _;
    }

    /// LOGIC ///

    function setAddressProvider(address addressProvider) external onlyOwner {
        _addressProvider = IAddressProvider(addressProvider);
    }

    function getAddressProvider() external view returns (address) {
        return address(_addressProvider);
    }

    function setTransferRestriction(bool restricted) external onlyOwner {
        _transferRestricted = restricted;
    }

    function burn(address account, uint256 amount) external initialized checkMintBurnRestriction {
        _burn(account, amount);
    }

    function mint(address account, uint256 amount) external initialized checkMintBurnRestriction {
        _mint(account, amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override initialized checkTransferRestriction(msg.sender, to) returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override initialized checkTransferRestriction(from, to) returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}
