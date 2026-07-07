// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BalanceDelta, PoolKey, SwapParams} from './Types.sol';

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

  /// @notice All interactions on the contract that account deltas require unlocking. A caller that calls `unlock` must implement
  /// `IUnlockCallback(msg.sender).unlockCallback(data)`, where they interact with the remaining functions on this contract.
  /// @dev The only functions callable without an unlocking are `initialize` and `updateDynamicLPFee`
  /// @param data Any data to pass to the callback, via `IUnlockCallback(msg.sender).unlockCallback(data)`
  /// @return The data returned by the call to `IUnlockCallback(msg.sender).unlockCallback(data)`
  function unlock(bytes calldata data) external returns (bytes memory);

  /// @notice Swap against the given pool
  /// @param key The pool to swap in
  /// @param params The parameters for swapping
  /// @param hookData The data to pass through to the swap hooks
  /// @return swapDelta The balance delta of the address swapping
  /// @dev Swapping on low liquidity pools may cause unexpected swap amounts when liquidity available is less than amountSpecified.
  /// Additionally note that if interacting with hooks that have the BEFORE_SWAP_RETURNS_DELTA_FLAG or AFTER_SWAP_RETURNS_DELTA_FLAG
  /// the hook may alter the swap input/output. Integrators should perform checks on the returned swapDelta.
  function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
    external
    returns (BalanceDelta swapDelta);

  /// @notice Writes the current ERC20 balance of the specified currency to transient storage
  /// This is used to checkpoint balances for the manager and derive deltas for the caller.
  /// @dev This MUST be called before any ERC20 tokens are sent into the contract, but can be skipped
  /// for native tokens because the amount to settle is determined by the sent value.
  /// However, if an ERC20 token has been synced and not settled, and the caller instead wants to settle
  /// native funds, this function can be called with the native currency to then be able to settle the native currency
  function sync(address currency) external;

  /// @notice Called by the user to net out some value owed to the user
  /// @dev Will revert if the requested amount is not available, consider using `mint` instead
  /// @dev Can also be used as a mechanism for free flash loans
  /// @param currency The currency to withdraw from the pool manager
  /// @param to The address to withdraw to
  /// @param amount The amount of currency to withdraw
  function take(address currency, address to, uint256 amount) external;

  /// @notice Called by the user to pay what is owed
  /// @return paid The amount of currency settled
  function settle() external payable returns (uint256 paid);

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
