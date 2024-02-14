// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAddressProvider} from "./interfaces/IAddressProvider.sol";
import {TimeLock, TimeLockedAddress} from "./lib/TimeLock.sol";

contract AddressProvider is AccessControl, IAddressProvider {
    using TimeLock for TimeLockedAddress;

    uint256 public immutable timeLockDelay;

    TimeLockedAddress internal _exchangeAdapter;
    TimeLockedAddress internal _priceOracle;
    TimeLockedAddress internal _marketOracle;
    TimeLockedAddress internal _registry;
    TimeLockedAddress internal _dvpPositionManager;
    TimeLockedAddress internal _vaultProxy;
    TimeLockedAddress internal _feeManager;
    TimeLockedAddress internal _vaultAccessNFT;
    TimeLockedAddress internal _dvpAccessNFT;

    bytes32 public constant ROLE_GOD = keccak256("ROLE_GOD");
    bytes32 public constant ROLE_ADMIN = keccak256("ROLE_ADMIN");

    error AddressZero();

    event ChangedExchangeAdapter(address newValue, address oldValue);
    event ChangedPriceOracle(address newValue, address oldValue);
    event ChangedMarketOracle(address newValue, address oldValue);
    event ChangedRegistry(address newValue, address oldValue);
    event ChangedPositionManager(address newValue, address oldValue);
    event ChangedVaultProxy(address newValue, address oldValue);
    event ChangedFeeManager(address newValue, address oldValue);
    event ChangedVaultAccessNFT(address newValue, address oldValue);
    event ChangedDVPAccessNFT(address newValue, address oldValue);

    constructor(uint256 timeLockDelay_) AccessControl() {
        timeLockDelay = timeLockDelay_;

        _setRoleAdmin(ROLE_GOD, ROLE_GOD);
        _setRoleAdmin(ROLE_ADMIN, ROLE_GOD);

        _grantRole(ROLE_GOD, msg.sender);
    }

    function _checkZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert AddressZero();
        }
    }

    function setExchangeAdapter(address exchangeAdapter_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(exchangeAdapter_);

        address previous = _exchangeAdapter.proposed;
        _exchangeAdapter.set(exchangeAdapter_, timeLockDelay);

        emit ChangedExchangeAdapter(exchangeAdapter_, previous);
    }

    function exchangeAdapter() external view returns (address) {
        return _exchangeAdapter.get();
    }

    function setPriceOracle(address priceOracle_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(priceOracle_);

        address previous = _priceOracle.proposed;
        _priceOracle.set(priceOracle_, timeLockDelay);

        emit ChangedPriceOracle(priceOracle_, previous);
    }

    function priceOracle() external view returns (address) {
        return _priceOracle.get();
    }

    function setMarketOracle(address marketOracle_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(marketOracle_);

        address previous = _marketOracle.proposed;
        _marketOracle.set(marketOracle_, timeLockDelay);

        emit ChangedMarketOracle(marketOracle_, previous);
    }

    function marketOracle() external view returns (address) {
        return _marketOracle.get();
    }

    function setRegistry(address registry_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(registry_);

        address previous = _registry.proposed;
        _registry.set(registry_, timeLockDelay);

        emit ChangedRegistry(registry_, previous);
    }

    function registry() external view returns (address) {
        return _registry.get();
    }

    function setDvpPositionManager(address posManager_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(posManager_);

        address previous = _dvpPositionManager.proposed;
        _dvpPositionManager.set(posManager_, timeLockDelay);

        emit ChangedPositionManager(posManager_, previous);
    }

    function dvpPositionManager() external view returns (address) {
        return _dvpPositionManager.get();
    }

    function setVaultProxy(address vaultProxy_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(vaultProxy_);

        address previous = _vaultProxy.proposed;
        _vaultProxy.set(vaultProxy_, timeLockDelay);

        emit ChangedVaultProxy(vaultProxy_, previous);
    }

    function vaultProxy() external view returns (address) {
        return _vaultProxy.get();
    }

    function setFeeManager(address feeManager_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(feeManager_);

        address previous = _feeManager.proposed;
        _feeManager.set(feeManager_, timeLockDelay);

        emit ChangedFeeManager(feeManager_, previous);
    }

    function feeManager() external view returns (address) {
        return _feeManager.get();
    }

    function setVaultAccessNFT(address vaultAccessNFT_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(vaultAccessNFT_);

        address previous = _vaultAccessNFT.proposed;
        _vaultAccessNFT.set(vaultAccessNFT_, timeLockDelay);

        emit ChangedVaultAccessNFT(vaultAccessNFT_, previous);
    }

    function vaultAccessNFT() external view returns (address) {
        return _vaultAccessNFT.get();
    }

    function setDVPAccessNFT(address dvpAccessNFT_) external {
        _checkRole(ROLE_ADMIN);
        _checkZeroAddress(dvpAccessNFT_);

        address previous = _dvpAccessNFT.proposed;
        _dvpAccessNFT.set(dvpAccessNFT_, timeLockDelay);

        emit ChangedDVPAccessNFT(dvpAccessNFT_, previous);
    }

    function dvpAccessNFT() external view returns (address) {
        return _dvpAccessNFT.get();
    }

}
