// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/interfaces/ICommon.sol';
import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import '../interfaces/hooks/IKSSmartIntentHook.sol';

import './types/ActionData.sol';
import './types/IntentCoreData.sol';

library HookLibrary {
  using TokenHelper for address;

  // @notice Emit the ERC20/Native fee and volume
  event RecordFeeAndVolume(
    address indexed token, address indexed feeRecipient, uint256 fee, uint256 volume
  );

  function beforeExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    address feeRecipient,
    ActionData calldata actionData
  ) internal returns (uint256[] memory fees, bytes memory beforeExecutionData) {
    (fees, beforeExecutionData) = IKSSmartIntentHook(intentData.coreData.hook).beforeExecution(
      intentHash, intentData, actionData
    );

    if (actionData.erc20Ids.length != fees.length) {
      revert ICommon.MismatchedArrayLengths();
    }

    for (uint256 i = 0; i < actionData.erc20Ids.length; i++) {
      emit RecordFeeAndVolume(
        intentData.tokenData.erc20Data[actionData.erc20Ids[i]].token,
        feeRecipient,
        fees[i],
        actionData.erc20Amounts[i]
      );
    }
  }

  function afterExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    address feeRecipient,
    bytes memory beforeExecutionData,
    bytes memory actionResult
  ) internal {
    (address[] memory tokens, uint256[] memory fees, uint256[] memory amounts, address recipient) =
    IKSSmartIntentHook(intentData.coreData.hook).afterExecution(
      intentHash, intentData, beforeExecutionData, actionResult
    );

    if (tokens.length != fees.length) {
      revert ICommon.MismatchedArrayLengths();
    }
    if (tokens.length != amounts.length) {
      revert ICommon.MismatchedArrayLengths();
    }

    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i].safeTransfer(recipient, amounts[i]);
      tokens[i].safeTransfer(feeRecipient, fees[i]);

      emit RecordFeeAndVolume(tokens[i], feeRecipient, fees[i], amounts[i] + fees[i]);
    }
  }
}
