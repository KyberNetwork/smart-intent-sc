// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Interface for the PoolManager
interface IPoolManager {
  /// @notice Called by external contracts to access granular pool state
  /// @param slot Key of slot to sload
  /// @return value The value of the slot as bytes32
  function extsload(bytes32 slot) external view returns (bytes32 value);

  /// @notice Called by external contracts to access granular pool state
  /// @param startSlot Key of slot to start sloading from
  /// @param nSlots Number of slots to load into return value
  /// @return values List of loaded values.
  function extsload(bytes32 startSlot, uint256 nSlots)
    external
    view
    returns (bytes32[] memory values);

  /// @notice Called by external contracts to access sparse pool state
  /// @param slots List of slots to SLOAD from.
  /// @return values List of loaded values.
  function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values);

  /// @notice Called by external contracts to access transient storage of the contract
  /// @param slot Key of slot to tload
  /// @return value The value of the slot as bytes32
  function exttload(bytes32 slot) external view returns (bytes32 value);

  /// @notice Called by external contracts to access sparse transient pool state
  /// @param slots List of slots to tload
  /// @return values List of loaded values
  function exttload(bytes32[] calldata slots) external view returns (bytes32[] memory values);

  /// @notice Thrown when a currency is not netted out after the contract is unlocked
  error CurrencyNotSettled();

  /// @notice Thrown when trying to interact with a non-initialized pool
  error PoolNotInitialized();

  /// @notice Thrown when unlock is called, but the contract is already unlocked
  error AlreadyUnlocked();

  /// @notice Thrown when a function is called that requires the contract to be unlocked, but it is not
  error ManagerLocked();

  /// @notice Pools are limited to type(int16).max tickSpacing in #initialize, to prevent overflow
  error TickSpacingTooLarge(int24 tickSpacing);

  /// @notice Pools must have a positive non-zero tickSpacing passed to #initialize
  error TickSpacingTooSmall(int24 tickSpacing);

  /// @notice PoolKey must have currencies where address(currency0) < address(currency1)
  error CurrenciesOutOfOrderOrEqual(address currency0, address currency1);

  /// @notice Thrown when a call to updateDynamicLPFee is made by an address that is not the hook,
  /// or on a pool that does not have a dynamic swap fee.
  error UnauthorizedDynamicLPFeeUpdate();

  /// @notice Thrown when trying to swap amount of 0
  error SwapAmountCannotBeZero();

  ///@notice Thrown when native currency is passed to a non native settlement
  error NonzeroNativeValue();

  /// @notice Thrown when `clear` is called with an amount that is not exactly equal to the open currency delta.
  error MustClearExactPositiveDelta();
}
