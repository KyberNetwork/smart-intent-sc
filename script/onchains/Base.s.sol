// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

import '../Base.s.sol';
import 'src/interfaces/IKSSwapRouter.sol';
import 'src/validators/KSPriceBasedDCAIntentValidator.sol';
import 'src/validators/KSSwapIntentValidator.sol';
import 'src/validators/KSTimeBasedDCAIntentValidator.sol';
import 'test/harness/KSSessionIntentRouterHarness.sol';

contract BaseOnchainScript is BaseScript {
  using stdJson for string;

  //swapData
  address tokenIn;
  address tokenOut;
  uint256 amountIn;
  uint256 minAmountOut;
  address recipient;
  bytes callData;

  //validationData
  uint256[] amountIns;
  uint256[] amountOutLimits;

  address operator;
  address mainWallet;
  address sessionWallet;
  uint256 startTime;
  uint256 endTime;
  address swapRouter;
  KSSessionIntentRouterHarness router;
  address validator;

  function _prepareData() internal {
    string memory root = vm.projectRoot();
    uint256 chainId;
    assembly ("memory-safe") {
      chainId := chainid()
    }
    console.log('chainId is %s', chainId);

    address[] memory operators = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/router-operators.json')), chainId
    );

    operator = operators[0];

    address[] memory inputAddresses = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/inputAddresses.json')), chainId
    );

    swapRouter = inputAddresses[0];
    router = KSSessionIntentRouterHarness(inputAddresses[1]);
    validator = inputAddresses[2];
    mainWallet = inputAddresses[3];
    sessionWallet = inputAddresses[4];

    //read data for swap
    string memory tokenInKey = 'tokenIn';
    string memory tokenOutKey = 'tokenOut';
    string memory amountInKey = 'amountIn';
    string memory minAmountOutKey = 'minAmountOut';
    string memory recipientKey = 'recipient';
    string memory callDataKey = 'callData';

    tokenIn =
      _readAddress(string(abi.encodePacked(root, '/script/configs/swapData.json')), tokenInKey);
    tokenOut =
      _readAddress(string(abi.encodePacked(root, '/script/configs/swapData.json')), tokenOutKey);
    amountIn =
      _readUint(string(abi.encodePacked(root, '/script/configs/swapData.json')), amountInKey);
    minAmountOut =
      _readUint(string(abi.encodePacked(root, '/script/configs/swapData.json')), minAmountOutKey);
    recipient =
      _readAddress(string(abi.encodePacked(root, '/script/configs/swapData.json')), recipientKey);
    callData =
      _readBytes(string(abi.encodePacked(root, '/script/configs/swapData.json')), callDataKey);
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
      mainAddress: mainWallet,
      delegatedAddress: sessionWallet,
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
