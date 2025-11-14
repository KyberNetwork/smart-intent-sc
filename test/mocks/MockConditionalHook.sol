// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ActionData} from '../../src/types/ActionData.sol';
import {IntentData} from '../../src/types/IntentData.sol';
import 'src/hooks/base/BaseConditionalHook.sol';

contract MockConditionalHook is BaseConditionalHook {
  modifier checkTokenLengths(ActionData calldata actionData) override {
    _;
  }

  function beforeExecution(bytes32, IntentData calldata, ActionData calldata actionData)
    external
    pure
    returns (uint256[] memory fees, bytes memory)
  {
    fees = new uint256[](actionData.erc20Ids.length);
  }

  function afterExecution(bytes32, IntentData calldata, bytes calldata, bytes calldata)
    external
    pure
    returns (address[] memory, uint256[] memory, uint256[] memory, address)
  {}
}
