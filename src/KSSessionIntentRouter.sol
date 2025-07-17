// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './KSSessionIntentRouterAccounting.sol';
import './KSSessionIntentRouterNonces.sol';
import './KSSessionIntentRouterTypeHashes.sol';

import '@openzeppelin-contracts/utils/Address.sol';
import '@openzeppelin-contracts/utils/ReentrancyGuardTransient.sol';
import '@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol';

contract KSSessionIntentRouter is
  KSSessionIntentRouterAccounting,
  KSSessionIntentRouterNonces,
  KSSessionIntentRouterTypeHashes,
  ReentrancyGuardTransient
{
  using Address for address;

  address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

  mapping(bytes32 => IntentCoreData) public intents;

  mapping(bytes32 => bool) public whitelistedActions;

  mapping(address => bool) public whitelistedValidators;

  constructor(
    address initialAdmin,
    address[] memory initialGuardians,
    address[] memory initialRescuers
  ) KSSessionIntentRouterAccounting(initialAdmin, initialGuardians, initialRescuers) {}

  /// @inheritdoc IKSSessionIntentRouter
  function whitelistActions(
    address[] calldata actionContracts,
    bytes4[] calldata actionSelectors,
    bool grantOrRevoke
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    for (uint256 i = 0; i < actionContracts.length; i++) {
      whitelistedActions[keccak256(abi.encodePacked(actionContracts[i], actionSelectors[i]))] =
        grantOrRevoke;

      emit WhitelistAction(actionContracts[i], actionSelectors[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IKSSessionIntentRouter
  function whitelistValidators(address[] calldata validators, bool grantOrRevoke)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    for (uint256 i = 0; i < validators.length; i++) {
      whitelistedValidators[validators[i]] = grantOrRevoke;

      emit WhitelistValidator(validators[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IKSSessionIntentRouter
  function delegate(IntentData calldata intentData) public {
    require(intentData.coreData.mainAddress == _msgSender(), NotMainAddress());
    _delegate(intentData, 0);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function revoke(bytes32 intentHash) public {
    IntentCoreData storage intent = intents[intentHash];
    require(intent.mainAddress == _msgSender(), NotMainAddress());

    intent.mainAddress = DEAD_ADDRESS;

    emit RevokeIntent(intentHash);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function revoke(IntentData calldata intentData) public {
    require(intentData.coreData.mainAddress == _msgSender(), NotMainAddress());
    bytes32 intentHash = _hashTypedIntentData(intentData);

    intents[intentHash].mainAddress = DEAD_ADDRESS;

    emit RevokeIntent(intentHash);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function execute(
    bytes32 intentHash,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) public {
    _execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function executeWithSignedIntent(
    IntentData calldata intentData,
    bytes memory maSignature,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) public {
    bytes32 intentHash = _hashTypedIntentData(intentData);
    require(
      SignatureChecker.isValidSignatureNow(intentData.coreData.mainAddress, intentHash, maSignature),
      InvalidMainAddressSignature()
    );
    _delegate(intentData, intentHash);
    _execute(intentHash, daSignature, guardian, gdSignature, actionData);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function hashTypedIntentData(IntentData calldata intentData) public view returns (bytes32) {
    return _hashTypedIntentData(intentData);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function hashTypedActionData(ActionData calldata actionData) public view returns (bytes32) {
    return _hashTypedActionData(actionData);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function getERC1155Allowance(bytes32 intentHash, address token, uint256 tokenId)
    public
    view
    returns (uint256)
  {
    return erc1155Allowances[intentHash][token][tokenId];
  }

  /// @inheritdoc IKSSessionIntentRouter
  function getERC20Allowance(bytes32 intentHash, address token) public view returns (uint256) {
    return erc20Allowances[intentHash][token];
  }

  /// @inheritdoc IKSSessionIntentRouter
  function getERC721Approval(bytes32 intentHash, address token, uint256 tokenId)
    public
    view
    returns (bool)
  {
    return erc721Approvals[intentHash][token][tokenId];
  }

  function _delegate(IntentData calldata intentData, bytes32 intentHash) internal {
    if (intentHash == 0) intentHash = _hashTypedIntentData(intentData);
    address mainAddress = intents[intentHash].mainAddress;
    require(mainAddress == address(0), IntentExistedOrRevoked());
    require(
      intentData.coreData.actionContracts.length == intentData.coreData.actionSelectors.length,
      LengthMismatch()
    );

    intents[intentHash] = intentData.coreData;

    _approveTokens(intentHash, intentData.tokenData, mainAddress);

    emit DelegateIntent(
      intentData.coreData.mainAddress, intentData.coreData.delegatedAddress, intentData
    );
  }

  function _execute(
    bytes32 intentHash,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) internal nonReentrant {
    IntentCoreData storage intent = intents[intentHash];
    require(intent.mainAddress != DEAD_ADDRESS, IntentRevoked());
    require(block.timestamp >= intent.startTime, ExecuteTooEarly());
    require(block.timestamp <= intent.endTime, ExecuteTooLate());
    require(block.timestamp <= actionData.deadline, ExecuteTooLate());
    require(
      actionData.actionSelectorId < intent.actionContracts.length,
      InvalidActionSelectorId(actionData.actionSelectorId)
    );
    _checkRole(KSRoles.GUARDIAN_ROLE, guardian);

    _useUnorderedNonce(intentHash, actionData.nonce);

    bytes32 actionHash = _hashTypedActionData(actionData);
    if (_msgSender() != intent.delegatedAddress) {
      require(
        SignatureChecker.isValidSignatureNow(intent.delegatedAddress, actionHash, daSignature),
        InvalidDelegatedAddressSignature()
      );
    }
    if (_msgSender() != guardian) {
      require(
        SignatureChecker.isValidSignatureNow(guardian, actionHash, gdSignature),
        InvalidGuardianSignature()
      );
    }
    require(whitelistedValidators[intent.validator], NonWhitelistedValidator(intent.validator));
    bytes memory beforeExecutionData = IKSSessionIntentValidator(intent.validator)
      .validateBeforeExecution(intentHash, intent, actionData);

    address actionContract = intent.actionContracts[actionData.actionSelectorId];
    bytes4 actionSelector = intent.actionSelectors[actionData.actionSelectorId];

    bytes32 actionContractAndSelectorHash =
      keccak256(abi.encodePacked(actionContract, actionSelector));
    require(
      whitelistedActions[actionContractAndSelectorHash],
      NonWhitelistedAction(actionContract, actionSelector)
    );
    _collectTokens(intentHash, intent.mainAddress, actionContract, actionData.tokenData);

    bytes memory actionResult =
      actionContract.functionCall(abi.encodePacked(actionSelector, actionData.actionCalldata));
    IKSSessionIntentValidator(intent.validator).validateAfterExecution(
      intentHash, intent, beforeExecutionData, actionResult
    );

    emit ExecuteIntent(intentHash, actionData, actionResult);
  }
}
