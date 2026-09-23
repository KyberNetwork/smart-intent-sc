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
import {
  IPullOracleReferenceHooks
} from 'pull-oracle-consumer/src/interfaces/IPullOracleReferenceHooks.sol';
import {PullOracleCodec} from 'pull-oracle-consumer/src/libraries/PullOracleCodec.sol';
import {
  PullOracleReferenceHooks
} from 'pull-oracle-consumer/src/libraries/PullOracleReferenceHooks.sol';
import {PullOracleSignature} from 'pull-oracle-consumer/src/libraries/PullOracleSignature.sol';
import {TokenOracle} from 'src/types/OracleConfig.sol';

contract AtlasOracleAdapter is IOracleAdapter, PullOracleConsumerStandardStorage, ManagementBase {
  using CalldataDecoder for bytes;
  using SlotDerivation for bytes32;
  using TransientSlot for bytes32;
  using TransientSlot for TransientSlot.AddressSlot;
  using TransientSlot for TransientSlot.Uint256Slot;

  /// @dev Offsets within a feed's slots: [price, timestamp, signer].
  uint256 internal constant TIMESTAMP_OFFSET = 1;
  uint256 internal constant SIGNER_OFFSET = 2;

  /// @dev Length of a well formed `additionalData`: three words
  ///      [feedId, maxFutureDrift, expectedSigner].
  uint256 internal constant ADDITIONAL_DATA_LENGTH = 96;

  /// @notice `oracle.additionalData` is not the full [feedId, maxFutureDrift, expectedSigner].
  error InvalidOracleAdditionalData();

  /// @notice The feed was signed by an authorized signer, but not the one the intent pinned.
  error UnexpectedFeedSigner(address expected, address actual);

  /// @dev Transient namespace holding `feedId => [price, timestamp]`.
  bytes32 internal immutable PRICES_SLOT =
    SlotDerivation.erc7201Slot('kyberswap.storage.AtlasOracleAdapter.prices');

  constructor(address initialAdmin, address[] memory initialSigners)
    PullOracleConsumerStandardStorage(
      uint8(PullOracleReferenceHooks.DEFAULT_MAX_PACKAGE_COUNT),
      uint48(PullOracleReferenceHooks.DEFAULT_MAX_DELAY),
      uint48(PullOracleReferenceHooks.DEFAULT_MAX_FUTURE_DRIFT),
      initialSigners
    )
    ManagementBase(0, initialAdmin)
  {}

  /**
   * @notice Verifies the Atlas signed payload appended to this call's calldata and caches each
   *         feed for the rest of the transaction.
   * @param feedIds The feeds to cache; each must be in the payload.
   */
  function updatePrices(bytes4[] calldata feedIds) external {
    if (feedIds.length == 0) return;

    (uint256[] memory prices, uint256[] memory timestamps) = _getVerifiedFeedDataBatch(feedIds);

    address signer = _recoverPayloadSigner();

    for (uint256 i = 0; i < feedIds.length; i++) {
      bytes32 slot = _feedSlot(feedIds[i]);
      slot.asUint256().tstore(prices[i]);
      slot.offset(TIMESTAMP_OFFSET).asUint256().tstore(timestamps[i]);
      slot.offset(SIGNER_OFFSET).asAddress().tstore(signer);
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
   * @dev `oracle.additionalData` is
   *      `abi.encode(bytes4 feedId, uint256 maxFutureDrift, address expectedSigner)`
   */
  function getPrice(TokenOracle calldata oracle) external view returns (uint256 price) {
    bytes calldata additionalData = oracle.additionalData;
    if (additionalData.length < ADDITIONAL_DATA_LENGTH) revert InvalidOracleAdditionalData();

    bytes4 feedId = bytes4(additionalData.decodeBytes32());
    bytes32 slot = _feedSlot(feedId);

    price = slot.asUint256().tload();
    if (price == 0) revert InvalidOraclePrice();

    uint256 updatedAt = slot.offset(TIMESTAMP_OFFSET).asUint256().tload();
    if (updatedAt + oracle.source.maxStaleness() < block.timestamp) revert StaleOraclePrice();

    if (updatedAt > block.timestamp + additionalData.decodeUint256(1)) {
      revert IPullOracleReferenceHooks.PriceFeedFutureDrift(feedId, updatedAt, block.timestamp);
    }

    address expectedSigner = additionalData.decodeAddress(2);
    if (expectedSigner != address(0)) {
      address signer = slot.offset(SIGNER_OFFSET).asAddress().tload();
      if (signer != expectedSigner) revert UnexpectedFeedSigner(expectedSigner, signer);
    }
  }

  function _recoverPayloadSigner() private view returns (address) {
    (uint256 payloadStart, uint256 payloadEnd) =
      PullOracleCodec._parseMetadata(_getMaxPackageCount());
    return PullOracleSignature._recoverSigner(payloadStart, payloadEnd);
  }

  function _feedSlot(bytes4 feedId) private view returns (bytes32) {
    return PRICES_SLOT.deriveMapping(bytes32(feedId));
  }
}
