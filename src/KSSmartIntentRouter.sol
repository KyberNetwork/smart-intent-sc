// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './KSSmartIntentRouterAccounting.sol';
import './KSSmartIntentRouterNonces.sol';

import './interfaces/actions/IKSSwapRouterV2.sol';
import './interfaces/actions/IKSSwapRouterV3.sol';
import './interfaces/actions/IKSZapRouter.sol';

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

  IKSGenericForwarder public immutable forwarder;

  constructor(
    address initialAdmin,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    address _forwarder
  ) ManagementBase(0, initialAdmin) {
    _batchGrantRole(KSRoles.GUARDIAN_ROLE, initialGuardians);
    _batchGrantRole(KSRoles.RESCUER_ROLE, initialRescuers);
    forwarder = IKSGenericForwarder(_forwarder);
  }

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

    _validateActionData(intent, daSignature, guardian, gdSignature, hashTypedActionData(actionData));

    (uint256[] memory fees, bytes memory beforeExecutionData) =
      HookLibrary.beforeExecution(intentHash, intent, actionData);

    address actionContract = intent.actionContracts[actionData.actionSelectorId];
    bytes4 actionSelector = intent.actionSelectors[actionData.actionSelectorId];

    if (!whitelistedActionContracts[actionContract]) {
      revert NotWhitelistedActionContract(actionContract);
    }

    IKSGenericForwarder _forwarder = _needForwarder(actionSelector);
    _collectTokens(
      intentHash,
      intent.mainAddress,
      actionContract,
      actionData.tokenData,
      _forwarder,
      fees,
      actionData.approvalFlags
    );

    bytes memory actionResult;
    {
      bytes memory data = abi.encodePacked(actionSelector, actionData.actionCalldata);
      if (address(_forwarder) != address(0)) {
        actionResult = _forwarder.forward(actionContract, data);
      } else {
        actionResult = actionContract.functionCall(data);
      }
    }

    HookLibrary.afterExecution(intentHash, intent, beforeExecutionData, actionResult);

    emit ExecuteIntent(intentHash, actionData, actionResult);
    emit ExtraData(intentHash, actionData.extraData);
  }

  function _needForwarder(bytes4 selector) internal view returns (IKSGenericForwarder) {
    if (
      selector == IKSSwapRouterV2.swap.selector
        || selector == IKSSwapRouterV2.swapSimpleMode.selector
        || selector == IKSSwapRouterV3.swap.selector || selector == IKSZapRouter.zap.selector
    ) {
      return IKSGenericForwarder(address(0));
    }
    return forwarder;
  }

  function _validateActionData(
    IntentCoreData calldata intent,
    bytes memory daSignature,
    address guardian,
    bytes memory gdSignature,
    bytes32 actionHash
  ) internal view {
    if (msg.sender != intent.delegatedAddress) {
      if (!SignatureChecker.isValidSignatureNow(intent.delegatedAddress, actionHash, daSignature)) {
        revert InvalidDelegatedAddressSignature();
      }
    }
    if (msg.sender != guardian) {
      if (!SignatureChecker.isValidSignatureNow(guardian, actionHash, gdSignature)) {
        revert InvalidGuardianSignature();
      }
    }
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
