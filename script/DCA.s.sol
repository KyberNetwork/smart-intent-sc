// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';

import 'test/harness/KSSessionIntentRouterHarness.sol';

import 'src/validators/KSPriceBasedDCAIntentValidator.sol';
import 'src/validators/KSSwapIntentValidator.sol';
import 'src/validators/KSTimeBasedDCAIntentValidator.sol';

contract DCAScript is BaseScript {
  using SafeERC20 for IERC20;

  address tokenIn;
  address tokenOut;
  uint256[] amountIns;
  uint256[] amountOutLimits;
  address recipient;

  address operator;
  address mainWallet;
  address sessionWallet;
  uint256 startTime;
  uint256 endTime;
  address swapRouter;
  KSSessionIntentRouterHarness router;
  address validator;

  function priceBased() external {
    string memory root = vm.projectRoot();
    uint256 chainId;
    assembly ("memory-safe") {
      chainId := chainid()
    }
    console.log('chainId is %s', chainId);

    address[] memory initAddresses = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/initAddresses.json')), chainId
    );
    operator = initAddresses[1];

    address[] memory inputAddresses = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/inputAddresses.json')), chainId
    );

    swapRouter = inputAddresses[0];
    router = KSSessionIntentRouterHarness(inputAddresses[1]);
    validator = inputAddresses[2];
    mainWallet = inputAddresses[3];
    sessionWallet = inputAddresses[4];
    startTime = 1_744_274_000;
    endTime = 1_744_280_000;

    bytes memory swapData =
      _readBytes(string(abi.encodePacked(root, '/script/configs/swapData.json')), chainId);

    //update deadline
    IKSSwapRouter.SwapExecutionParams memory params =
      abi.decode(swapData, (IKSSwapRouter.SwapExecutionParams));
    SwapExecutorDescription memory desc = abi.decode(params.targetData, (SwapExecutorDescription));
    desc.deadline = endTime - 100;
    params.targetData = abi.encode(desc);
    swapData = abi.encode(params);

    //prepare data for validator
    tokenIn = params.desc.srcToken;
    tokenOut = params.desc.dstToken;
    amountIns.push(params.desc.amount);
    amountOutLimits.push(params.desc.minReturnAmount << 128 | 2 ** 128 - 1);
    recipient = params.desc.dstReceiver;

    IKSSessionIntentRouter.IntentData memory intentData = _getIntentData();
    IKSSessionIntentRouter.ActionData memory actionData =
      _getActionData(intentData.tokenData, swapData);

    vm.startBroadcast(vm.envUint('MAIN_WALLET_PRIVATE_KEY'));
    IERC20(tokenIn).safeIncreaseAllowance(address(router), params.desc.amount);
    vm.stopBroadcast();

    vm.startBroadcast();
    router.executeWithSignedIntent(
      intentData, _getMWSignature(intentData), _getSWSignature(actionData), operator, '', actionData
    );
    vm.stopBroadcast();
  }

  function _getIntentData()
    internal
    view
    returns (IKSSessionIntentRouter.IntentData memory intentData)
  {
    KSPriceBasedDCAIntentValidator.DCAValidationData memory validationData;
    validationData.srcToken = tokenIn;
    validationData.dstToken = tokenOut;
    validationData.amountIns = amountIns;
    validationData.amountOutLimits = amountOutLimits;
    validationData.recipient = recipient;

    IKSSessionIntentRouter.IntentCoreData memory coreData = IKSSessionIntentRouter.IntentCoreData({
      mainWallet: mainWallet,
      sessionWallet: sessionWallet,
      startTime: startTime,
      endTime: endTime,
      actionContract: swapRouter,
      actionSelector: IKSSwapRouter.swap.selector,
      validator: validator,
      validationData: abi.encode(validationData)
    });

    IKSSessionIntentRouter.TokenData memory tokenData;
    tokenData.erc20Data = new IKSSessionIntentRouter.ERC20Data[](1);
    tokenData.erc20Data[0] =
      IKSSessionIntentRouter.ERC20Data({token: tokenIn, amount: amountIns[0]});

    intentData = IKSSessionIntentRouter.IntentData({coreData: coreData, tokenData: tokenData});
  }

  function _getActionData(
    IKSSessionIntentRouter.TokenData memory tokenData,
    bytes memory actionCalldata
  ) internal view returns (IKSSessionIntentRouter.ActionData memory actionData) {
    actionData = IKSSessionIntentRouter.ActionData({
      tokenData: tokenData,
      actionCalldata: actionCalldata,
      validatorData: abi.encode(0), //swapNo, but this script only swap once
      deadline: endTime - 100
    });
  }

  function _getMWSignature(IKSSessionIntentRouter.IntentData memory intentData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 intentHash = router.hashTypedIntentData(intentData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint('MAIN_WALLET_PRIVATE_KEY'), intentHash);
    return abi.encodePacked(r, s, v);
  }

  function _getSWSignature(IKSSessionIntentRouter.ActionData memory actionData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 actionHash = router.hashTypedActionData(actionData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint('SESSION_WALLET_PRIVATE_KEY'), actionHash);
    return abi.encodePacked(r, s, v);
  }
}
