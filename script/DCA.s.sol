// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';

contract DCAScript is BaseScript {
  using SafeERC20 for IERC20;

  function priceBased() external {
    _prepareData();

    //prepare data for validation
    amountIns.push(amountIn);
    amountOutLimits.push(minAmountOut << 128 | 2 ** 128 - 1);
    startTime = block.timestamp;
    endTime = type(uint32).max;

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();
    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, callData);

    vm.startBroadcast(vm.envUint('MAIN_WALLET_PRIVATE_KEY'));
    IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);
    vm.stopBroadcast();

    vm.startBroadcast();
    router.executeWithSignedIntent(
      intentData, _getMWSignature(intentData), _getSWSignature(actionData), operator, '', actionData
    );
    vm.stopBroadcast();
  }
}
