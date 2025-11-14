// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ICommon} from 'ks-common-sc/src/interfaces/ICommon.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {IKSSmartIntentHook} from '../interfaces/hooks/IKSSmartIntentHook.sol';

import {ActionData} from '../types/ActionData.sol';
import {ERC20Data, ERC20DataLibrary} from '../types/ERC20Data.sol';
import {IntentData} from '../types/IntentData.sol';

library HookLibrary {
  using TokenHelper for address;
  using ERC20DataLibrary for address;

  function beforeExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    ActionData calldata actionData
  ) internal returns (uint256[] memory fees, bytes memory beforeExecutionData) {
    (fees, beforeExecutionData) = IKSSmartIntentHook(intentData.coreData.hook)
      .beforeExecution(intentHash, intentData, actionData);

    if (actionData.erc20Ids.length != fees.length) {
      revert ICommon.MismatchedArrayLengths();
    }
  }

  function afterExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    ActionData calldata actionData,
    bytes memory beforeExecutionData,
    bytes memory actionResult
  ) internal {
    (address[] memory tokens, uint256[] memory fees, uint256[] memory amounts, address recipient) = IKSSmartIntentHook(
        intentData.coreData.hook
      ).afterExecution(intentHash, intentData, beforeExecutionData, actionResult);

    if (tokens.length != fees.length) {
      revert ICommon.MismatchedArrayLengths();
    }
    if (tokens.length != amounts.length) {
      revert ICommon.MismatchedArrayLengths();
    }

    if (fees.length == 0) {
      return;
    }

    if (tokens.length != actionData.feeInfo.partnerFeeConfigs.length) {
      revert ICommon.MismatchedArrayLengths();
    }

    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i].safeTransfer(recipient, amounts[i]);

      tokens[i].collectFeeAfterExecution(
        amounts[i] + fees[i],
        fees[i],
        actionData.feeInfo.partnerFeeConfigs[i],
        actionData.feeInfo.protocolRecipient
      );
    }
  }
}
