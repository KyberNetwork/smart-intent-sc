// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import {IOracleAdapter} from '../interfaces/oracle/IOracleAdapter.sol';
import {ManagementBase} from 'ks-common-sc/src/base/ManagementBase.sol';
import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';
import {SlotDerivation} from 'openzeppelin-contracts/contracts/utils/SlotDerivation.sol';
import {TransientSlot} from 'openzeppelin-contracts/contracts/utils/TransientSlot.sol';
import {
  PullOracleConsumerStandardStorage
} from 'pull-oracle-consumer/src/PullOracleConsumerStandardStorage.sol';
import {TokenOracle} from 'src/types/OracleConfig.sol';

contract AtlasOracleAdapter is IOracleAdapter, PullOracleConsumerStandardStorage, ManagementBase {
  using CalldataDecoder for bytes;
  using SlotDerivation for bytes32;
  using TransientSlot for bytes32;
  using TransientSlot for TransientSlot.Uint256Slot;

  uint8 internal constant DEFAULT_MAX_PACKAGE_COUNT = type(uint8).max;
  uint48 internal constant DEFAULT_MAX_DELAY = 180;
  uint48 internal constant DEFAULT_MAX_FUTURE_DRIFT = 60;

  /// @dev Offset of the timestamp within a feed's slots: [price, timestamp].
  uint256 internal constant TIMESTAMP_OFFSET = 1;

  /// @dev Transient namespace holding `feedId => [price, timestamp]`.
  bytes32 internal immutable PRICES_SLOT =
    SlotDerivation.erc7201Slot('kyberswap.storage.AtlasOracleAdapter.prices');

  constructor(address initialAdmin, address[] memory initialSigners)
    PullOracleConsumerStandardStorage(
      DEFAULT_MAX_PACKAGE_COUNT, DEFAULT_MAX_DELAY, DEFAULT_MAX_FUTURE_DRIFT, initialSigners
    )
    ManagementBase(0, initialAdmin)
  {}

  /**
   * @notice Verifies the Atlas signed payload appended to this call's calldata and caches each
   *         feed for the rest of the transaction.
   * @param feedIds The feeds to cache; each must be in the payload.
   */
  function updatePrices(bytes4[] calldata feedIds) external {
    (uint256[] memory prices, uint256[] memory timestamps) = _getVerifiedFeedDataBatch(feedIds);

    for (uint256 i = 0; i < feedIds.length; i++) {
      bytes32 slot = _feedSlot(feedIds[i]);
      slot.asUint256().tstore(prices[i]);
      slot.offset(TIMESTAMP_OFFSET).asUint256().tstore(timestamps[i]);
    }
  }

  /// @notice Adds or removes an authorized Atlas signer.
  function setSignerStatus(address signer, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setSignerStatus(signer, status);
  }

  /// @notice Sets the max age, in seconds, of a price accepted by `updatePrices`.
  function setMaxDelay(uint48 newMaxDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setMaxDelay(newMaxDelay);
  }

  /// @notice Sets how far, in seconds, a price timestamp may be ahead of the block.
  function setMaxFutureDrift(uint48 newMaxFutureDrift) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setMaxFutureDrift(newMaxFutureDrift);
  }

  /// @notice Sets the max number of price packages in one payload.
  function setMaxPackageCount(uint8 newMaxPackageCount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setMaxPackageCount(newMaxPackageCount);
  }

  /**
   * @inheritdoc IOracleAdapter
   */
  function getPrice(TokenOracle calldata oracle) external view returns (uint256 price) {
    bytes32 slot = _feedSlot(bytes4(oracle.additionalData.decodeBytes32()));

    price = slot.asUint256().tload();
    if (price == 0) revert InvalidOraclePrice();

    uint256 updatedAt = slot.offset(TIMESTAMP_OFFSET).asUint256().tload();
    if (updatedAt + oracle.source.maxStaleness() < block.timestamp) revert StaleOraclePrice();
  }

  function _feedSlot(bytes4 feedId) private view returns (bytes32) {
    return PRICES_SLOT.deriveMapping(bytes32(feedId));
  }
}
