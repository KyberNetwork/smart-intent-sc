// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './KSSessionIntentRouterAccounting.sol';
import './KSSessionIntentRouterTypeHashes.sol';

import 'openzeppelin-contracts/utils/Address.sol';
import 'openzeppelin-contracts/utils/ReentrancyGuardTransient.sol';
import 'openzeppelin-contracts/utils/cryptography/SignatureChecker.sol';

contract KSSessionIntentRouter is
  KSSessionIntentRouterAccounting,
  KSSessionIntentRouterTypeHashes,
  ReentrancyGuardTransient
{
  using Address for address;

  address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

  mapping(bytes32 => IntentCoreData) public intents;

  mapping(bytes32 => bool) whitelistedActions;

  mapping(address => bool) whitelistedValidators;

  constructor(address initialOwner, address[] memory initialGuardians)
    KSSessionIntentRouterAccounting(initialOwner, initialGuardians)
  {}

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

  function whitelistValidators(address[] calldata validators, bool grantOrRevoke) public onlyOwner {
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

  function _delegate(IntentData calldata intentData, bytes32 intentHash) internal {
    if (intentHash == 0) intentHash = _hashTypedIntentData(intentData);
    require(intents[intentHash].mainAddress == address(0), IntentAlreadyExists());
    {
      bytes32 actionHash = keccak256(
        abi.encodePacked(intentData.coreData.actionContract, intentData.coreData.actionSelector)
      );
      require(
        whitelistedActions[actionHash],
        NonWhitelistedAction(intentData.coreData.actionContract, intentData.coreData.actionSelector)
      );
    }
    require(
      whitelistedValidators[intentData.coreData.validator],
      NonWhitelistedValidator(intentData.coreData.validator)
    );
    intents[intentHash] = intentData.coreData;

    _approveTokens(intentHash, intentData.tokenData);

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
    require(guardians[guardian], KyberSwapRole.KSRoleNotGuardian(guardian));

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

    bytes memory beforeExecutionData = IKSSessionIntentValidator(intent.validator)
      .validateBeforeExecution(intentHash, intent, actionData);
    _collectTokens(intentHash, intent.mainAddress, intent.actionContract, actionData.tokenData);
    bytes memory actionResult = intent.actionContract.functionCall(
      abi.encodePacked(intent.actionSelector, actionData.actionCalldata)
    );
    IKSSessionIntentValidator(intent.validator).validateAfterExecution(
      intentHash, intent, beforeExecutionData, actionResult
    );

    emit ExecuteIntent(intentHash, actionData, actionResult);
  }
}
