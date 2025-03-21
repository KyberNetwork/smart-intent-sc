// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './KSSessionIntentRouterAccounting.sol';
import './KSSessionIntentRouterTypeHashes.sol';

import 'openzeppelin-contracts/utils/Address.sol';
import 'openzeppelin-contracts/utils/ReentrancyGuard.sol';
import 'openzeppelin-contracts/utils/cryptography/SignatureChecker.sol';

contract KSSessionIntentRouter is
  KSSessionIntentRouterAccounting,
  KSSessionIntentRouterTypeHashes,
  ReentrancyGuard
{
  using Address for address;

  address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

  mapping(bytes32 => IntentCoreData) public intents;

  constructor(
    address initialOwner,
    address[] memory initialOperators,
    address[] memory initialGuardians
  ) KSSessionIntentRouterAccounting(initialOwner, initialOperators, initialGuardians) {}

  /// @inheritdoc IKSSessionIntentRouter
  function delegate(IntentData calldata intentData) public {
    require(intentData.coreData.mainWallet == _msgSender(), NotMainWallet());
    _delegate(intentData, 0);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function revoke(bytes32 intentHash) public {
    intents[intentHash].mainWallet = DEAD_ADDRESS;
  }

  /// @inheritdoc IKSSessionIntentRouter
  function execute(
    bytes32 intentHash,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) public {
    _execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  /// @inheritdoc IKSSessionIntentRouter
  function executeWithSignedIntent(
    IntentData calldata intentData,
    bytes memory mwSignature,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) public {
    bytes32 intentHash = _hashTypedIntentData(intentData);
    require(
      SignatureChecker.isValidSignatureNow(intentData.coreData.mainWallet, intentHash, mwSignature),
      InvalidMainWalletSignature()
    );
    _delegate(intentData, intentHash);
    _execute(intentHash, swSignature, operator, opSignature, actionData);
  }

  function _delegate(IntentData calldata intentData, bytes32 intentHash) internal {
    if (intentHash == 0) intentHash = _hashTypedIntentData(intentData);
    require(intents[intentHash].mainWallet == address(0), IntentAlreadyExists());
    intents[intentHash] = intentData.coreData;

    _approveTokens(intentHash, intentData.tokenData);
  }

  function _execute(
    bytes32 intentHash,
    bytes memory swSignature,
    address operator,
    bytes memory opSignature,
    ActionData calldata actionData
  ) internal nonReentrant {
    IntentCoreData storage intent = intents[intentHash];
    require(intent.mainWallet != DEAD_ADDRESS, IntentRevoked());
    require(block.timestamp >= intent.startTime, ExecuteTooEarly());
    require(block.timestamp <= intent.endTime, ExecuteTooLate());
    require(block.timestamp <= actionData.deadline, ExecuteTooLate());
    require(operators[operator], KyberSwapRole.KSRoleNotOperator(operator));

    bytes32 actionHash = _hashTypedActionData(actionData);
    if (_msgSender() != intent.sessionWallet) {
      require(
        SignatureChecker.isValidSignatureNow(intent.sessionWallet, actionHash, swSignature),
        InvalidSessionWalletSignature()
      );
    }
    if (_msgSender() != operator) {
      require(
        SignatureChecker.isValidSignatureNow(operator, actionHash, opSignature),
        InvalidOperatorSignature()
      );
    }

    _spendTokens(intentHash, intent.mainWallet, intent.actionContract, actionData.tokenData);
    bytes memory beforeExecutionData = IKSSessionIntentValidator(intent.validator)
      .validateBeforeExecution(intent, actionData.actionCalldata);
    bytes memory actionResult = intent.actionContract.functionCall(
      abi.encodePacked(intent.actionSelector, actionData.actionCalldata)
    );
    IKSSessionIntentValidator(intent.validator).validateAfterExecution(
      intent, beforeExecutionData, actionResult
    );
    _refundTokens(intent.mainWallet, actionData.tokenData);
  }
}
