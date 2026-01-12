// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IKSGenericRouter
/// @notice Generic interface for routers used by KyberSwap
interface IKSGenericRouter {
  /// @notice Executes with given data
  function ksExecute(bytes calldata data) external payable returns (bytes memory);
}
