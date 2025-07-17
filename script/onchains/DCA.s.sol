// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';
import {SafeERC20} from '@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol';

contract DCAScript is BaseOnchainScript {
  using SafeERC20 for IERC20;

  function priceBased() external {
    _prepareData('KSPriceBasedDCAIntentValidator');

    //prepare data for validation
    amountIns.push(amountIn);
    amountOutLimits.push((1 << 128) | (2 ** 128 - 1));
    startTime = block.timestamp;
    endTime = type(uint32).max;

    KSPriceBasedDCAIntentValidator.DCAValidationData memory validationData;
    validationData.srcToken = tokenIn;
    validationData.dstToken = tokenOut;
    validationData.amountIns = amountIns;
    validationData.amountOutLimits = amountOutLimits;
    validationData.recipient = recipient;

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(abi.encode(validationData));
    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, callData);

    vm.startBroadcast(mainWalletPrivateKey);
    IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);
    vm.stopBroadcast();

    vm.startBroadcast(guardianPrivateKey);
    router.executeWithSignedIntent(
      intentData, _getMWSignature(intentData), _getSWSignature(actionData), guardian, '', actionData
    );
    vm.stopBroadcast();
  }

  function timeBased() external {
    _prepareData('KSTimeBasedDCAIntentValidator');

    //prepare data for validation
    uint32 duration = uint32(1 days);
    uint32 startPeriod = uint32(60);

    uint256 executionParams = 3; //numSwaps;
    executionParams = (executionParams << 32) | duration; //duration;
    executionParams = (executionParams << 32) | startPeriod; //startPeriod;
    executionParams = (executionParams << 32) | block.timestamp; //firstTimestamp;

    startTime = block.timestamp;
    endTime = type(uint32).max;

    KSTimeBasedDCAIntentValidator.DCAValidationData memory validationData;
    validationData.srcToken = tokenIn;
    validationData.dstToken = tokenOut;
    validationData.amountIn = amountIn;
    validationData.amountOutLimits = (1 << 128) | (2 ** 128 - 1);
    validationData.executionParams = executionParams;
    validationData.recipient = recipient;

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData(abi.encode(validationData));
    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, callData);

    vm.startBroadcast(mainWalletPrivateKey);
    IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);
    vm.stopBroadcast();

    vm.startBroadcast(guardianPrivateKey);
    router.executeWithSignedIntent(
      intentData, _getMWSignature(intentData), _getSWSignature(actionData), guardian, '', actionData
    );
    vm.stopBroadcast();
  }
}
