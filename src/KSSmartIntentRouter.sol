// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './KSSmartIntentRouterAccounting.sol';
import './KSSmartIntentRouterNonces.sol';

import './libraries/HookLibrary.sol';

import 'openzeppelin-contracts/contracts/utils/Address.sol';
import 'openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol';

import 'openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol';
import 'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

contract KSSmartIntentRouter is
  KSSmartIntentRouterAccounting,
  KSSmartIntentRouterNonces,
  ReentrancyGuardTransient,
  EIP712('KSSmartIntentRouter', '1')
{
  using Address for address;
  using TokenHelper for address;

  mapping(bytes32 => IntentStatus) public intentStatuses;

  mapping(address => bool) public whitelistedActionContracts;

  constructor(
    address initialAdmin,
    address[] memory initialGuardians,
    address[] memory initialRescuers
  ) KSSmartIntentRouterAccounting(initialAdmin, initialGuardians, initialRescuers) {}

  receive() external payable {}

  /// @inheritdoc IKSSmartIntentRouter
  function hashTypedIntentData(IntentData calldata intentData) public view returns (bytes32) {
    return _hashTypedDataV4(intentData.hash());
  }

  /// @inheritdoc IKSSmartIntentRouter
  function hashTypedActionData(ActionData calldata actionData) public view returns (bytes32) {
    return _hashTypedDataV4(actionData.hash());
  }

  /// @inheritdoc IKSSmartIntentRouter
  function whitelistActionContracts(address[] calldata actionContracts, bool grantOrRevoke) public {
    for (uint256 i = 0; i < actionContracts.length; i++) {
      whitelistedActionContracts[actionContracts[i]] = grantOrRevoke;
    }
  }

  /// @inheritdoc IKSSmartIntentRouter
  function delegate(IntentData calldata intentData) public {
    if (intentData.coreData.mainAddress != msg.sender) {
      revert NotMainAddress();
    }

    _delegate(intentData, hashTypedIntentData(intentData));
  }

  /// @inheritdoc IKSSmartIntentRouter
  function revoke(IntentData calldata intentData) public {
    if (intentData.coreData.mainAddress != msg.sender) {
      revert NotMainAddress();
    }

    bytes32 intentHash = hashTypedIntentData(intentData);
    intentStatuses[intentHash] = IntentStatus.REVOKED;

    emit RevokeIntent(intentHash);
  }

  /// @inheritdoc IKSSmartIntentRouter
  function execute(
    IntentData calldata intentData,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) public {
    bytes32 intentHash = hashTypedIntentData(intentData);
    _execute(intentHash, intentData.coreData, daSignature, guardian, gdSignature, actionData);
  }

  /// @inheritdoc IKSSmartIntentRouter
  function executeWithSignedIntent(
    IntentData calldata intentData,
    bytes memory maSignature,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    ActionData calldata actionData
  ) public {
    bytes32 intentHash = hashTypedIntentData(intentData);
    if (
      !SignatureChecker.isValidSignatureNow(intentData.coreData.mainAddress, intentHash, maSignature)
    ) {
      revert InvalidMainAddressSignature();
    }

    _delegate(intentData, intentHash);
    _execute(intentHash, intentData.coreData, daSignature, guardian, gdSignature, actionData);
  }

  function _delegate(IntentData calldata intentData, bytes32 intentHash)
    internal
    checkLengths(
      intentData.coreData.actionContracts.length,
      intentData.coreData.actionSelectors.length
    )
  {
    IntentCoreData calldata intent = intentData.coreData;

    _checkIntentStatus(intentHash, IntentStatus.NOT_DELEGATED);

    intentStatuses[intentHash] = IntentStatus.DELEGATED;
    _approveTokens(intentHash, intentData.tokenData, intent.mainAddress);

    emit DelegateIntent(intent.mainAddress, intent.delegatedAddress, intentData);
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
    if (actionData.actionSelectorId >= intent.actionContracts.length) {
      revert InvalidActionSelectorId(actionData.actionSelectorId);
    }
    if (block.timestamp > actionData.deadline) {
      revert ActionExpired();
    }
    _checkRole(KSRoles.GUARDIAN_ROLE, guardian);

    _useUnorderedNonce(intentHash, actionData.nonce);

    actionData.validate(hashTypedActionData(actionData), intent, daSignature, guardian, gdSignature);

    bytes memory beforeExecutionData = HookLibrary.beforeExecution(intentHash, intent, actionData);

    address actionContract = intent.actionContracts[actionData.actionSelectorId];
    bytes4 actionSelector = intent.actionSelectors[actionData.actionSelectorId];

    if (!whitelistedActionContracts[actionContract]) {
      revert NotWhitelistedActionContract(actionContract);
    }
    _collectTokens(intentHash, intent.mainAddress, actionContract, actionData.tokenData);

    bytes memory actionResult =
      actionContract.functionCall(abi.encodePacked(actionSelector, actionData.actionCalldata));

    HookLibrary.afterExecution(intentHash, intent, beforeExecutionData, actionResult);

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
