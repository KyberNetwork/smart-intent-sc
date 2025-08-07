// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/interfaces/ICommon.sol';
import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import '../interfaces/hooks/IKSSmartIntentHook.sol';

import './types/ActionData.sol';
import './types/IntentCoreData.sol';

library HookLibrary {
  using TokenHelper for address;

  /// @notice Emitted when a fee on a token is collected
  event CollectFee(address token, uint256 fee);

  function beforeExecution(
    bytes32 intentHash,
    IntentCoreData calldata intent,
    ActionData calldata actionData
  ) internal returns (uint256[] memory fees, bytes memory beforeExecutionData) {
    (fees, beforeExecutionData) =
      IKSSmartIntentHook(intent.hook).beforeExecution(intentHash, intent, actionData);

    if (actionData.tokenData.erc20Data.length != fees.length) {
      revert ICommon.MismatchedArrayLengths();
    }

    for (uint256 i = 0; i < actionData.tokenData.erc20Data.length; i++) {
      emit CollectFee(actionData.tokenData.erc20Data[i].token, fees[i]);
    }
  }

  function afterExecution(
    bytes32 intentHash,
    IntentCoreData calldata intent,
    bytes memory beforeExecutionData,
    bytes memory actionResult
  ) internal {
    (address[] memory tokens, uint256[] memory fees, uint256[] memory amounts, address recipient) =
    IKSSmartIntentHook(intent.hook).afterExecution(
      intentHash, intent, beforeExecutionData, actionResult
    );

    if (tokens.length != fees.length) {
      revert ICommon.MismatchedArrayLengths();
    }
    if (tokens.length != amounts.length) {
      revert ICommon.MismatchedArrayLengths();
    }

    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i].safeTransfer(recipient, amounts[i]);

      emit CollectFee(tokens[i], fees[i]);
    }
  }
}
