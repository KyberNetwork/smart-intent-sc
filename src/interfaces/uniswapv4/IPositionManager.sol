// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IPoolManager.sol';
import 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

/// @title IPositionManager
/// @notice Interface for the PositionManager contract
interface IPositionManager is IERC721 {
  /// @notice Thrown when the caller is not approved to modify a position
  error NotApproved(address caller);
  /// @notice Thrown when the block.timestamp exceeds the user-provided deadline
  error DeadlinePassed(uint256 deadline);
  /// @notice Thrown when calling transfer, subscribe, or unsubscribe when the PoolManager is unlocked.
  /// @dev This is to prevent hooks from being able to trigger notifications at the same time the position is being modified.
  error PoolManagerMustBeLocked();

  /// @param tokenId the ERC721 tokenId
  /// @return liquidity the position's liquidity, as a liquidityAmount
  /// @dev this value can be processed as an amount0 and amount1 by using the LiquidityAmounts library
  function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);

  /// @param tokenId the ERC721 tokenId
  /// @return PositionInfo a uint256 packed value holding information about the position including the range (tickLower, tickUpper)
  /// @return poolKey the pool key of the position
  function getPoolAndPositionInfo(uint256 tokenId) external view returns (PoolKey memory, uint256);

  function poolManager() external view returns (IPoolManager);

  function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
}
