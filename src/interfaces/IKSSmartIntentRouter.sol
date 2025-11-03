// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../types/ActionData.sol';
import '../types/IntentData.sol';

interface IKSSmartIntentRouter {
  /// @notice Thrown when total partner fee is greater than 100%
  error InvalidFeeConfig();

  /// @notice Thrown when the caller is not the main address
  error NotMainAddress();

  /// @notice Thrown when the action is expired
  error ActionExpired();

  /// @notice Thrown when the intent has not been delegated
  error IntentNotDelegated();

  /// @notice Thrown when the intent has already been delegated
  error IntentDelegated();

  /// @notice Thrown when the intent has already been revoked
  error IntentRevoked();

  /// @notice Thrown when the signature is not from the main address
  error InvalidMainAddressSignature();

  /// @notice Thrown when the signature is not from the session wallet
  error InvalidDelegatedAddressSignature();

  /// @notice Thrown when the signature is not from the guardian
  error InvalidGuardianSignature();

  /// @notice Thrown when the action contract and selector not found in intent
  error InvalidActionSelectorId(uint256 actionSelectorId);

  /// @notice Thrown when a nonce has already been used
  error NonceAlreadyUsed(bytes32 intentHash, uint256 nonce);

  /// @notice Thrown when collecting more than the intent allowance for ERC20
  error ERC20InsufficientIntentAllowance(
    bytes32 intentHash, address token, uint256 allowance, uint256 needed
  );

  /// @notice Emitted when the forwarder is updated
  event UpdateForwarder(address newForwarder);

  /// @notice Emitted when an intent is delegated
  event DelegateIntent(
    address indexed mainAddress, address indexed delegatedAddress, IntentData intentData
  );

  /// @notice Emitted when an intent is revoked
  event RevokeIntent(bytes32 indexed intentHash);

  /// @notice Emitted when an intent is executed
  event ExecuteIntent(bytes32 indexed intentHash, ActionData actionData, bytes actionResult);

  /// @notice Emitted when a nonce is consumed
  event UseNonce(bytes32 indexed intentHash, uint256 nonce);

  /// @notice Emitted when the fee is collected before execution
  event RecordVolumeAndFees(
    address indexed token,
    address indexed protocolRecipient,
    FeeConfig[] partnerFeeConfigs,
    uint256 protocolFeeAmount,
    uint256[] partnersFeeAmounts,
    bool beforeExecution,
    uint256 totalAmount
  );

  enum IntentStatus {
    NOT_DELEGATED,
    DELEGATED,
    REVOKED
  }

  /**
   * @notice Delegate the intent to the delegated address
   * @param intentData The data for the intent
   */
  function delegate(IntentData calldata intentData) external;

  /**
   * @notice Revoke the delegated intent
   * @param intentData The intent data to revoke
   */
  function revoke(IntentData memory intentData) external;

  /**
   * @notice Execute the intent
   * @param intentData The data for the intent
   * @param daSignature The signature of the delegated address
   * @param guardian The address of the guardian
   * @param gdSignature The signature of the guardian
   * @param actionData The data for the action
   */
  function execute(
    IntentData calldata intentData,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) external;

  /**
   * @notice Execute the intent with the signed data and main address signature
   * @param intentData The data for the intent
   * @param maSignature The signature of the main address
   * @param daSignature The signature of the delegated address
   * @param guardian The address of the guardian
   * @param gdSignature The signature of the guardian
   * @param actionData The data for the action
   */
  function executeWithSignedIntent(
    IntentData calldata intentData,
    bytes memory maSignature,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) external;

  /**
   * @notice Return the ERC20 allowance for a specific intent
   * @param intentHash The hash of the intent
   * @param token The address of the ERC20 token
   * @return allowance The allowance for the specified token
   */
  function erc20Allowances(bytes32 intentHash, address token)
    external
    view
    returns (uint256 allowance);

  /**
   * @notice Update the forwarder address
   * @param newForwarder The new forwarder address
   */
  function updateForwarder(address newForwarder) external;

  /**
   * @notice Hash the intent data with EIP712
   * @param intentData The intent data
   * @return hash The hash of the intent data
   */
  function hashTypedIntentData(IntentData calldata intentData) external view returns (bytes32);

  /**
   * @notice Hash the action data with EIP712
   * @param actionData The action data
   * @return hash The hash of the action data
   */
  function hashTypedActionData(ActionData calldata actionData) external view returns (bytes32);

  /// @notice mapping of nonces consumed by each intent, where a nonce is a single bit on the 256-bit bitmap
  /// @dev word is at most type(uint248).max
  function nonces(bytes32 intentHash, uint256 word) external view returns (uint256 bitmap);
}
