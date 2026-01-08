// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {KSSmartIntentHasher} from './KSSmartIntentHasher.sol';
import {KSSmartIntentRouterAccounting} from './KSSmartIntentRouterAccounting.sol';
import {KSSmartIntentRouterNonces} from './KSSmartIntentRouterNonces.sol';

import {IKSSmartIntentRouter} from './interfaces/IKSSmartIntentRouter.sol';
import {IKSSwapRouterV2} from './interfaces/actions/IKSSwapRouterV2.sol';
import {IKSSwapRouterV3} from './interfaces/actions/IKSSwapRouterV3.sol';
import {IKSZapRouter} from './interfaces/actions/IKSZapRouter.sol';

import {HookLibrary} from './libraries/HookLibrary.sol';

import {ActionData} from './types/ActionData.sol';
import {ActionWitness} from './types/ActionWitness.sol';
import {IntentCoreData} from './types/IntentCoreData.sol';
import {IntentData} from './types/IntentData.sol';

import {IERC7913SignatureVerifier} from 'openzeppelin-contracts/contracts/interfaces/IERC7913.sol';
import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';
import {
  ReentrancyGuardTransient
} from 'openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol';
import {EIP712} from 'openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol';
import {
  SignatureChecker
} from 'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

import {ManagementBase} from 'ks-common-sc/src/base/ManagementBase.sol';
import {IKSGenericForwarder} from 'ks-common-sc/src/interfaces/IKSGenericForwarder.sol';
import {KSRoles} from 'ks-common-sc/src/libraries/KSRoles.sol';
import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';

contract KSSmartIntentRouter is
  KSSmartIntentRouterAccounting,
  KSSmartIntentRouterNonces,
  ReentrancyGuardTransient,
  EIP712('KSSmartIntentRouter', '1')
{
  using Address for address;
  using SignatureChecker for address;
  using CalldataDecoder for bytes;

  KSSmartIntentHasher internal immutable hasher;

  constructor(
    address initialAdmin,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    address[] memory initialActionContracts,
    address _forwarder
  ) ManagementBase(0, initialAdmin) {
    _batchGrantRole(KSRoles.GUARDIAN_ROLE, initialGuardians);
    _batchGrantRole(KSRoles.RESCUER_ROLE, initialRescuers);
    _batchGrantRole(ACTION_CONTRACT_ROLE, initialActionContracts);

    _updateForwarder(_forwarder);

    hasher = new KSSmartIntentHasher();
  }

  receive() external payable {}

  /// @inheritdoc IKSSmartIntentRouter
  function updateForwarder(address newForwarder) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateForwarder(newForwarder);
  }

  function _updateForwarder(address newForwarder) internal {
    forwarder = IKSGenericForwarder(newForwarder);

    emit UpdateForwarder(newForwarder);
  }

  /// @inheritdoc IKSSmartIntentRouter
  function delegate(IntentData calldata intentData) public {
    if (intentData.coreData.mainAddress != msg.sender) {
      revert NotMainAddress();
    }

    _delegate(intentData, _hashTypedDataV4(hasher.hashIntentData(intentData)));
  }

  /// @inheritdoc IKSSmartIntentRouter
  function revoke(IntentData calldata intentData) public {
    if (intentData.coreData.mainAddress != msg.sender) {
      revert NotMainAddress();
    }

    bytes32 intentHash = _hashTypedDataV4(hasher.hashIntentData(intentData));
    intentStatuses[intentHash] = IntentStatus.REVOKED;

    emit RevokeIntent(intentHash);
  }

  /// @inheritdoc IKSSmartIntentRouter
  function execute(
    IntentData calldata intentData,
    bytes calldata dkSignature,
    address guardian,
    bytes calldata gdSignature,
    ActionData calldata actionData
  ) public {
    bytes32 intentHash = _hashTypedDataV4(hasher.hashIntentData(intentData));
    _execute(intentHash, intentData, dkSignature, guardian, gdSignature, actionData);
  }

  /// @inheritdoc IKSSmartIntentRouter
  function executeWithSignedIntent(
    IntentData calldata intentData,
    bytes calldata maSignature,
    bytes calldata dkSignature,
    address guardian,
    bytes calldata gdSignature,
    ActionData calldata actionData
  ) public {
    bytes32 intentHash = _hashTypedDataV4(hasher.hashIntentData(intentData));
    if (!intentData.coreData.mainAddress.isValidSignatureNowCalldata(intentHash, maSignature)) {
      revert InvalidMainAddressSignature();
    }

    _delegate(intentData, intentHash);
    _execute(intentHash, intentData, dkSignature, guardian, gdSignature, actionData);
  }

  /// @inheritdoc IKSSmartIntentRouter
  function DOMAIN_SEPARATOR() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  function _delegate(IntentData calldata intentData, bytes32 intentHash)
    internal
    checkLengths(
      intentData.coreData.actionContracts.length, intentData.coreData.actionSelectors.length
    )
  {
    IntentCoreData calldata coreData = intentData.coreData;

    _checkIntentStatus(intentHash, IntentStatus.NOT_DELEGATED);

    intentStatuses[intentHash] = IntentStatus.DELEGATED;
    _approveTokens(intentHash, intentData.tokenData, coreData.mainAddress);

    emit DelegateIntent(coreData.mainAddress, coreData.delegatedKey, intentData);
  }

  function _execute(
    bytes32 intentHash,
    IntentData calldata intentData,
    bytes calldata dkSignature,
    address guardian,
    bytes calldata gdSignature,
    ActionData calldata actionData
  ) internal nonReentrant {
    _checkIntentStatus(intentHash, IntentStatus.DELEGATED);
    if (actionData.actionSelectorId >= intentData.coreData.actionContracts.length) {
      revert InvalidActionSelectorId(actionData.actionSelectorId);
    }
    if (block.timestamp > actionData.deadline) {
      revert ActionExpired();
    }
    _checkRole(KSRoles.GUARDIAN_ROLE, guardian);

    _useUnorderedNonce(intentHash, actionData.nonce);

    _validateActionData(intentData.coreData, actionData, dkSignature, guardian, gdSignature);

    (uint256[] memory fees, bytes memory beforeExecutionData) =
      HookLibrary.beforeExecution(intentHash, intentData, actionData);

    address actionContract = intentData.coreData.actionContracts[actionData.actionSelectorId];
    bytes4 actionSelector = intentData.coreData.actionSelectors[actionData.actionSelectorId];

    _checkRole(ACTION_CONTRACT_ROLE, actionContract);

    IKSGenericForwarder _forwarder = _needForwarder(actionSelector);
    _collectTokens(
      intentHash,
      intentData.coreData.mainAddress,
      actionContract,
      intentData.tokenData,
      actionData,
      _forwarder,
      fees
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

    HookLibrary.afterExecution(
      intentHash, intentData, actionData, beforeExecutionData, actionResult
    );

    emit ExecuteIntent(intentHash, actionData, actionResult);
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
    IntentCoreData calldata coreData,
    ActionData calldata actionData,
    bytes calldata dkSignature,
    address guardian,
    bytes calldata gdSignature
  ) internal view {
    bytes32 witnessHash = _hashTypedDataV4(hasher.hashActionWitness(coreData, actionData));

    if (coreData.signatureVerifier == address(0)) {
      /// @dev use ECDSA scheme
      address delegatedAddress = coreData.delegatedKey.decodeAddress();
      if (
        msg.sender != delegatedAddress
          && !delegatedAddress.isValidSignatureNowCalldata(witnessHash, dkSignature)
      ) {
        revert InvalidDelegatedKeySignature();
      }
    } else {
      if (
        IERC7913SignatureVerifier(coreData.signatureVerifier)
            .verify(coreData.delegatedKey, witnessHash, dkSignature)
          != IERC7913SignatureVerifier.verify.selector
      ) {
        revert InvalidDelegatedKeySignature();
      }
    }

    if (msg.sender != guardian) {
      if (!guardian.isValidSignatureNowCalldata(witnessHash, gdSignature)) {
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
