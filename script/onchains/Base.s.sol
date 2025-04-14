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

  uint256 internal constant DEFAULT_SLIPPAGE = 500;

  struct SwapRequest {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    address sender;
    address recipient;
    uint256 slippage;
  }

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

  address guardian;
  address mainWallet;
  address sessionWallet;
  uint256 startTime;
  uint256 endTime;
  address swapRouter;
  KSSessionIntentRouterHarness router;
  address validator;

  function _prepareData(string memory validatorType) internal {
    string memory root = vm.projectRoot();
    uint256 chainId;
    assembly ("memory-safe") {
      chainId := chainid()
    }
    console.log('chainId is %s', chainId);

    address[] memory guardians = _readAddressArray(
      string(abi.encodePacked(root, '/script/configs/router-guardians.json')), chainId
    );

    guardian = guardians[0];
    (address[] memory swapRouters,) = _readSwapRouterAddresses(
      string(abi.encodePacked(root, '/script/configs/swap-routers.json')), chainId
    );
    swapRouter = swapRouters[0];
    router = KSSessionIntentRouterHarness(
      _readAddress(string(abi.encodePacked(root, '/script/deployedAddresses/router.json')), chainId)
    );
    (string[] memory validators, address[] memory addresses) = _readValidatorAddresses(
      string(abi.encodePacked(root, '/script/deployedAddresses/validators.json')), chainId
    );

    for (uint256 i; i < validators.length; i++) {
      if (_compareStrings(validators[i], validatorType)) {
        validator = addresses[i];
        break;
      }
    }

    mainWallet =
      _readAddress(string(abi.encodePacked(root, '/script/configs/main-wallet.json')), chainId);
    sessionWallet =
      _readAddress(string(abi.encodePacked(root, '/script/configs/session-wallet.json')), chainId);

    //read data for swap
    tokenIn =
      _readAddress(string(abi.encodePacked(root, '/script/configs/swap-inputs.json')), 'tokenIn');
    tokenOut =
      _readAddress(string(abi.encodePacked(root, '/script/configs/swap-inputs.json')), 'tokenOut');
    amountIn =
      _readUint(string(abi.encodePacked(root, '/script/configs/swap-inputs.json')), 'amountIn');
    recipient =
      _readAddress(string(abi.encodePacked(root, '/script/configs/swap-inputs.json')), 'recipient');
    string memory chainName =
      _readString(string(abi.encodePacked(root, '/script/configs/chain-name.json')), chainId);

    (, callData,) = _getSwapCalldata(
      chainName,
      SwapRequest({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
        sender: guardian,
        recipient: recipient,
        slippage: DEFAULT_SLIPPAGE
      })
    );
  }

  function _getIntentData(bytes memory validationData)
    internal
    view
    returns (IKSSessionIntentRouter.IntentData memory intentData)
  {
    IKSSessionIntentRouter.IntentCoreData memory coreData = IKSSessionIntentRouter.IntentCoreData({
      mainAddress: mainWallet,
      delegatedAddress: sessionWallet,
      startTime: startTime,
      endTime: endTime,
      actionContract: swapRouter,
      actionSelector: IKSSwapRouter.swap.selector,
      validator: validator,
      validationData: validationData
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

  function _getSwapCalldata(string memory chain, SwapRequest memory req)
    internal
    returns (address, bytes memory, uint256)
  {
    string[] memory commandInput = new string[](15);

    commandInput[0] = 'script/onchains/GetSwapRoute.sh';
    commandInput[1] = '--chain';
    commandInput[2] = chain;
    commandInput[3] = '--token-in';
    commandInput[4] = vm.toString(req.tokenIn);
    commandInput[5] = '--token-out';
    commandInput[6] = vm.toString(req.tokenOut);
    commandInput[7] = '--amount-in';
    commandInput[8] = vm.toString(req.amountIn);
    commandInput[9] = '--sender';
    commandInput[10] = vm.toString(req.sender);
    commandInput[11] = '--recipient';
    commandInput[12] = vm.toString(req.recipient);
    commandInput[13] = '--slippage';
    commandInput[14] = vm.toString(req.slippage);

    string memory result = string(vm.ffi(commandInput));
    address routerAddress = result.readAddress('.routerAddress');
    bytes memory swapCallData = abi.decode(result.parseRaw('.callData'), (bytes));
    uint256 value = result.readUint('.value');

    return (routerAddress, swapCallData, value);
  }
}
