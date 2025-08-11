// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/hooks/base/BaseHook.sol';

contract MockHook is BaseHook {
  modifier checkTokenLengths(TokenData calldata tokenData) override {
    _;
  }

  function beforeExecution(bytes32, IntentCoreData calldata, ActionData calldata actionData)
    external
    pure
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    if (actionData.hookActionData.length > 0) {
      fees = abi.decode(actionData.hookActionData, (uint256[]));
      beforeExecutionData = actionData.extraData;
    } else {
      fees = new uint256[](actionData.tokenData.erc20Data.length);
    }
  }

  function afterExecution(
    bytes32,
    IntentCoreData calldata,
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
      (tokens, fees, amounts, recipient) =
        abi.decode(beforeExecutionData, (address[], uint256[], uint256[], address));
    }
  }
}
