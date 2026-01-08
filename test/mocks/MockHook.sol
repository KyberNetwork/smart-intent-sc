// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/hooks/base/BaseHook.sol';

import {ActionData} from '../../src/types/ActionData.sol';
import {IntentData} from '../../src/types/IntentData.sol';

contract MockHook is BaseHook {
  modifier checkTokenLengths(ActionData calldata actionData) override {
    _;
  }

  function beforeExecution(bytes32, IntentData calldata, ActionData calldata actionData)
    external
    pure
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    if (actionData.hookActionData.length > 0) {
      fees = abi.decode(actionData.hookActionData, (uint256[]));
      beforeExecutionData = actionData.extraData;
    } else {
      fees = new uint256[](actionData.erc20Ids.length);
    }
  }

  function afterExecution(
    bytes32,
    IntentData calldata,
    bytes calldata beforeExecutionData,
    bytes calldata
  )
    external
    pure
    returns (
      address[] memory tokens,
      uint256[] memory fees,
      uint256[] memory amounts,
      address recipient
    )
  {
    if (beforeExecutionData.length > 0) {
      (tokens, fees, amounts, recipient) = abi.decode(
        beforeExecutionData, (address[], uint256[], uint256[], address)
      );
    }
  }
}
