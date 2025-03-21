// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSSessionIntentRouter {
  /// @notice Thrown when the caller is not the main wallet
  error NotMainWallet();

  /// @notice Thrown when executing the intent before the start time
  error ExecuteTooEarly();

  /// @notice Thrown when executing the intent after the end time
  error ExecuteTooLate();

  /// @notice Thrown when the intent has already existed
  error IntentAlreadyExists();

  /// @notice Thrown when the intent has been revoked
  error IntentRevoked();

  /// @notice Thrown when the signature is not from the main wallet
  error InvalidMainWalletSignature();

  /// @notice Thrown when the signature is not from the session wallet
  error InvalidSessionWalletSignature();

  /// @notice Thrown when the signature is not from the operator
  error InvalidOperatorSignature();

  /// @notice Thrown when spending more than the intent allowance for ERC1155
  error ERC1155InsufficientIntentAllowance(
    bytes32 intentHash, address token, uint256 tokenId, uint256 allowance, uint256 needed
  );

  /// @notice Thrown when spending more than the intent allowance for ERC20
  error ERC20InsufficientIntentAllowance(
    bytes32 intentHash, address token, uint256 allowance, uint256 needed
  );

  /// @notice Thrown when spending unapproved ERC721
  error ERC721InsufficientIntentApproval(bytes32 intentHash, address token, uint256 tokenId);

  /**
   * @notice Data structure for ERC20 token
   * @param token The address of the ERC20 token
   * @param amount The amount of the ERC20 token
   * @param minRefundAmount The minimum amount of the ERC20 token to refund
   */
  struct ERC20Data {
    address token;
    uint256 amount;
    uint256 minRefundAmount;
  }

  /**
   * @notice Data structure for ERC721 token
   * @param token The address of the ERC721 token
   * @param tokenId The ID of the ERC721 token
   */
  struct ERC721Data {
    address token;
    uint256 tokenId;
  }

  /**
   * @notice Data structure for ERC1155 token
   * @param token The address of the ERC1155 token
   * @param tokenIds The IDs of the ERC1155 token
   * @param amounts The amounts of the ERC1155 token
   * @param minRefundAmounts The minimum amounts of the ERC1155 token to refund
   */
  struct ERC1155Data {
    address token;
    uint256[] tokenIds;
    uint256[] amounts;
    uint256[] minRefundAmounts;
  }

  /**
   * @notice Data structure for token data
   * @param erc1155Data The data for ERC1155 tokens
   * @param erc20Data The data for ERC20 tokens
   * @param erc721Data The data for ERC721 tokens
   */
  struct TokenData {
    ERC1155Data[] erc1155Data;
    ERC20Data[] erc20Data;
    ERC721Data[] erc721Data;
  }

  /**
   * @notice Data structure for core components of intent
   * @param mainWallet The address of the main wallet
   * @param sessionWallet The address of the session wallet
   * @param startTime The start time of the intent
   * @param endTime The end time of the intent
   * @param actionContract The address of the action contract
   * @param actionSelector The selector of the action function
   * @param validator The address of the validator
   * @param validationData The data for the validator
   */
  struct IntentCoreData {
    address mainWallet;
    address sessionWallet;
    uint256 startTime;
    uint256 endTime;
    address actionContract;
    bytes4 actionSelector;
    address validator;
    bytes validationData;
  }

  /**
   * @notice Data structure for intent data
   * @param coreData The core data for the intent
   * @param tokenData The token data for the intent
   */
  struct IntentData {
    IntentCoreData coreData;
    TokenData tokenData;
  }

  /**
   * @notice Data structure for action
   * @param tokenData The token data for the action
   * @param actionCalldata The calldata for the action
   * @param deadline The deadline for the action
   */
  struct ActionData {
    TokenData tokenData;
    bytes actionCalldata;
    uint256 deadline;
  }
  
  /**
   * @notice Delegate the intent to the session wallet
   * @param intentData The data for the intent
   */
  function delegate(IntentData calldata intentData) external;

  /**
   * @notice Revoke the delegated intent
   * @param intentHash The hash of the intent
   */
  function revoke(bytes32 intentHash) external;

  /**
   * @notice Execute the intent
   * @param intentHash The hash of the intent
   * @param swSignature The signature of the session wallet
   * @param operator The address of the operator
   * @param opSignature The signature of the operator
   * @param actionData The data for the action
   */
  function execute(
    bytes32 intentHash,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) external;

  /**
   * @notice Execute the intent with the signed data and main wallet signature
   * @param intentData The data for the intent
   * @param mwSignature The signature of the main wallet
   * @param swSignature The signature of the session wallet
   * @param operator The address of the operator
   * @param opSignature The signature of the operator
   * @param actionData The data for the action
   */
  function executeWithSignedIntent(
    IntentData calldata intentData,
    bytes memory mwSignature,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) external;
}
