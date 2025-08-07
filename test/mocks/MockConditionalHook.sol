// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/hooks/base/BaseConditionalHook.sol';

contract MockConditionalHook is BaseConditionalHook {
  modifier checkTokenLengths(TokenData calldata tokenData) override {
    _;
  }

  function beforeExecution(bytes32, IntentCoreData calldata, ActionData calldata actionData)
    external
    pure
    returns (uint256[] memory fees, bytes memory)
  {
    fees = new uint256[](actionData.tokenData.erc20Data.length);
  }

  function afterExecution(
    bytes32,
    IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata actionResult
  ) external pure returns (address[] memory, uint256[] memory, uint256[] memory, address) {}
}
