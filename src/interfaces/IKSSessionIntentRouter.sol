// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSSessionIntentRouter {
  /// @notice Thrown when the caller is not the main address
  error NotMainAddress();

  /// @notice Thrown when executing the intent before the start time
  error ExecuteTooEarly();

  /// @notice Thrown when executing the intent after the end time
  error ExecuteTooLate();

  /// @notice Thrown when the intent has already existed
  error IntentAlreadyExists();

  /// @notice Thrown when the intent has been revoked
  error IntentRevoked();

  /// @notice Thrown when the signature is not from the main address
  error InvalidMainAddressSignature();

  /// @notice Thrown when the signature is not from the session wallet
  error InvalidDelegatedAddressSignature();

  /// @notice Thrown when the signature is not from the guardian
  error InvalidGuardianSignature();

  /// @notice Thrown when the action is not whitelisted
  error NonWhitelistedAction(address actionContract, bytes4 actionSelector);

  /// @notice Thrown when the validator is not whitelisted
  error NonWhitelistedValidator(address validator);

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

  /// @notice Emitted when the whitelist status of an action is updated
  event WhitelistAction(
    address indexed actionContract, bytes4 indexed actionSelector, bool grantOrRevoke
  );

  /// @notice Emitted when the whitelist status of a validator is updated
  event WhitelistValidator(address indexed validator, bool grantOrRevoke);

  /// @notice Emitted when an intent is delegated
  event DelegateIntent(
    address indexed mainAddress, address indexed delegatedAddress, IntentData intentData
  );

  /// @notice Emitted when an intent is executed
  event ExecuteIntent(bytes32 indexed intentHash, ActionData actionData, bytes actionResult);

  /**
   * @notice Data structure for ERC20 token
   * @param token The address of the ERC20 token
   * @param amount The amount of the ERC20 token
   */
  struct ERC20Data {
    address token;
    uint256 amount;
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
   */
  struct ERC1155Data {
    address token;
    uint256[] tokenIds;
    uint256[] amounts;
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
   * @param mainAddress The main address
   * @param delegatedAddress The delegated address
   * @param startTime The start time of the intent
   * @param endTime The end time of the intent
   * @param actionContract The address of the action contract
   * @param actionSelector The selector of the action function
   * @param validator The address of the validator
   * @param validationData The data for the validator
   */
  struct IntentCoreData {
    address mainAddress;
    address delegatedAddress;
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
   * @param validatorData The data for the validator
   * @param deadline The deadline for the action
   */
  struct ActionData {
    TokenData tokenData;
    bytes actionCalldata;
    bytes validatorData;
    uint256 deadline;
  }

  /**
   * @notice Whitelist the actions
   * @param actionContracts The addresses of the action contracts
   * @param actionSelectors The selectors of the action functions
   * @param grantOrRevoke Whether to grant or revoke the actions
   */
  function whitelistActions(
    address[] calldata actionContracts,
    bytes4[] calldata actionSelectors,
    bool grantOrRevoke
  ) external;

  /**
   * @notice Whitelist the validators
   * @param validators The addresses of the validators
   * @param grantOrRevoke Whether to grant or revoke the validators
   */
  function whitelistValidators(address[] calldata validators, bool grantOrRevoke) external;

  /**
   * @notice Delegate the intent to the delegated address
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
   * @param daSignature The signature of the delegated address
   * @param guardian The address of the guardian
   * @param gdSignature The signature of the guardian
   * @param actionData The data for the action
   */
  function execute(
    bytes32 intentHash,
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
}
