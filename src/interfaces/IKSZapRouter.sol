// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSZapRouter {
  /// @dev Contains general data for zapping and validation
  /// @param zapFlags packed value of dexType (uint8) | srcType (uint8)
  /// @param srcInfo src position info
  /// @param zapInfo extra info, depends on each dex type
  /// @param extraData extra data to be used for validation
  struct ZapDescription {
    uint16 zapFlags;
    bytes srcInfo;
    bytes zapInfo;
    bytes extraData;
  }

  /// @dev Contains execution data for zapping
  /// @param validator validator address, must be whitelisted one
  /// @param executor zap executor address, must be whitelisted one
  /// @param deadline make sure the request is not expired yet
  /// @param executorData data for zap execution
  /// @param clientData for events and tracking purposes
  struct ZapExecutionData {
    address validator;
    address executor;
    uint32 deadline;
    bytes executorData;
    bytes clientData;
  }

  /// @notice collect token, execute and validate zap
  function zap(ZapDescription calldata _desc, ZapExecutionData calldata _exe)
    external
    payable
    returns (bytes memory zapResults);
}
