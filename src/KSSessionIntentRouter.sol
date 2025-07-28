// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './KSSessionIntentRouterAccounting.sol';
import './KSSessionIntentRouterNonces.sol';
import './KSSessionIntentRouterTypeHashes.sol';

import 'openzeppelin-contracts/utils/Address.sol';
import 'openzeppelin-contracts/utils/ReentrancyGuardTransient.sol';
import 'openzeppelin-contracts/utils/cryptography/SignatureChecker.sol';

contract KSSessionIntentRouter is
  KSSessionIntentRouterAccounting,
  KSSessionIntentRouterNonces,
  KSSessionIntentRouterTypeHashes,
  ReentrancyGuardTransient
{
  using Address for address;

  mapping(bytes32 => IntentStatus) public intentStatuses;

  mapping(bytes32 => bool) public whitelistedActions;

  mapping(address => bool) public whitelistedValidators;

  constructor(address initialOwner, address[] memory initialGuardians)
    KSSessionIntentRouterAccounting(initialOwner, initialGuardians)
  {}

  /// @inheritdoc IKSSessionIntentRouter
  function whitelistActions(
    address[] calldata actionContracts,
    bytes4[] calldata actionSelectors,
    bool grantOrRevoke
  ) public onlyOwner {
    for (uint256 i = 0; i < actionContracts.length; i++) {
      whitelistedActions[keccak256(abi.encodePacked(actionContracts[i], actionSelectors[i]))] =
        grantOrRevoke;

      emit WhitelistAction(actionContracts[i], actionSelectors[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IKSSessionIntentRouter
  function whitelistValidators(address[] calldata validators, bool grantOrRevoke) public onlyOwner {
    for (uint256 i = 0; i < validators.length; i++) {
      whitelistedValidators[validators[i]] = grantOrRevoke;

      emit WhitelistValidator(validators[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IKSSessionIntentRouter
  function delegate(IntentData calldata intentData) public {
    require(intentData.coreData.mainAddress == _msgSender(), NotMainAddress());

    _delegate(intentData, _hashTypedIntentData(intentData));
  }

  /// @inheritdoc IKSSessionIntentRouter
  function revoke(IntentData calldata intentData) public {
    require(intentData.coreData.mainAddress == _msgSender(), NotMainAddress());

    bytes32 intentHash = _hashTypedIntentData(intentData);
    intentStatuses[intentHash] = IntentStatus.REVOKED;

    emit RevokeIntent(intentHash);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function execute(
    IntentData calldata intentData,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) public {
    bytes32 intentHash = _hashTypedIntentData(intentData);
    _execute(intentHash, intentData.coreData, daSignature, guardian, gdSignature, actionData);
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
    _execute(intentHash, intentData.coreData, daSignature, guardian, gdSignature, actionData);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function hashTypedIntentData(IntentData calldata intentData) public view returns (bytes32) {
    return _hashTypedIntentData(intentData);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function hashTypedActionData(ActionData calldata actionData) public view returns (bytes32) {
    return _hashTypedActionData(actionData);
  }

  function _delegate(IntentData calldata intentData, bytes32 intentHash) internal {
    _checkIntentStatus(intentHash, IntentStatus.NOT_DELEGATED);
    require(
      intentData.coreData.actionContracts.length == intentData.coreData.actionSelectors.length,
      LengthMismatch()
    );

    intentStatuses[intentHash] = IntentStatus.DELEGATED;
    _approveTokens(intentHash, intentData.tokenData);

    emit DelegateIntent(
      intentData.coreData.mainAddress, intentData.coreData.delegatedAddress, intentData
    );
  }

  function _execute(
    bytes32 intentHash,
    IntentCoreData calldata intent,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) internal nonReentrant {
    _checkIntentStatus(intentHash, IntentStatus.DELEGATED);
    require(block.timestamp >= intent.startTime, ExecuteTooEarly());
    require(block.timestamp <= intent.endTime, ExecuteTooLate());
    require(block.timestamp <= actionData.deadline, ExecuteTooLate());
    require(guardians[guardian], KyberSwapRole.KSRoleNotGuardian(guardian));
    require(
      actionData.actionSelectorId < intent.actionContracts.length,
      InvalidActionSelectorId(actionData.actionSelectorId)
    );

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

  function _checkIntentStatus(bytes32 intentHash, IntentStatus expectedStatus) internal view {
    IntentStatus actualStatus = intentStatuses[intentHash];
    if (actualStatus != expectedStatus) {
      if (actualStatus == IntentStatus.DELEGATED) {
        revert IntentDelegated();
      } else if (actualStatus == IntentStatus.REVOKED) {
        revert IntentRevoked();
      } else {
        revert IntentNotDelegated();
      }
    }
  }
}
