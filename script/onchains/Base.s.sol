// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

import 'ks-common-sc/script/Base.s.sol';

import 'src/KSSmartIntentRouter.sol';
import 'src/hooks/swap/KSPriceBasedDCAHook.sol';
import 'src/hooks/swap/KSSwapHook.sol';
import 'src/hooks/swap/KSTimeBasedDCAHook.sol';
import 'src/hooks/zap-out/KSZapOutUniswapV2Hook.sol';
import 'src/hooks/zap-out/KSZapOutUniswapV3Hook.sol';
import 'src/hooks/zap-out/KSZapOutUniswapV4Hook.sol';

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

  struct SwapInputs {
    uint256 amountIn;
    address recipient;
    address tokenIn;
    address tokenOut;
  }

  //swapData
  address tokenIn;
  address tokenOut;
  uint256 amountIn;
  address recipient;
  bytes4 selector;
  bytes callData;

  //validationData
  uint256[] amountIns;
  uint256[] amountOutLimits;

  address guardian;
  uint256 guardianPrivateKey;
  address mainWallet;
  uint256 mainWalletPrivateKey;
  address sessionWallet;
  uint256 sessionWalletPrivateKey;
  uint256 startTime;
  uint256 endTime;
  address swapRouter;
  KSSmartIntentRouter router;
  address hook;

  function _prepareData(string memory hookType) internal {
    (guardian, guardianPrivateKey) = makeAddrAndKey('guardian');

    address[] memory actionContracts = _readAddressArray('whitelisted-contracts');
    swapRouter = actionContracts[0];
    router = KSSmartIntentRouter(payable(_readAddress('router')));

    //add guardian
    {
      address admin = _readAddress('router-admin');
      vm.startBroadcast(admin);
      router.grantRole(KSRoles.GUARDIAN_ROLE, guardian);
      vm.stopBroadcast();
    }

    hook = _readAddress(hookType);

    mainWalletPrivateKey = vm.envUint('MAIN_WALLET_PRIVATE_KEY');
    mainWallet = vm.addr(mainWalletPrivateKey);

    (sessionWallet, sessionWalletPrivateKey) = makeAddrAndKey('sessionWallet');

    //read data for swap
    SwapInputs memory swapInputs = _readSwapInputs();
    string memory chainName = _readString('chain-name');

    tokenIn = swapInputs.tokenIn;
    tokenOut = swapInputs.tokenOut;
    amountIn = swapInputs.amountIn;
    recipient = swapInputs.recipient;
    (, selector, callData,) = _getSwapCalldata(
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

  function _getIntentData(bytes memory hookIntentData)
    internal
    view
    returns (IntentData memory intentData)
  {
    IntentCoreData memory coreData = IntentCoreData({
      mainAddress: mainWallet,
      delegatedAddress: sessionWallet,
      actionContracts: _toArray(swapRouter),
      actionSelectors: _toArray(selector),
      hook: hook,
      hookIntentData: hookIntentData
    });

    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](1);
    tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: amountIn, permitData: ''});

    intentData = IntentData({coreData: coreData, tokenData: tokenData, extraData: ''});
  }

  function _getActionData(TokenData memory tokenData, bytes memory actionCalldata)
    internal
    view
    returns (ActionData memory actionData)
  {
    actionData = ActionData({
      tokenData: tokenData,
      approvalFlags: type(uint256).max,
      actionSelectorId: 0,
      actionCalldata: actionCalldata,
      hookActionData: abi.encode(0), //swapNo, but this script only swap once
      extraData: '',
      deadline: endTime - 100,
      nonce: 0
    });
  }

  function _getMWSignature(IntentData memory intentData) internal view returns (bytes memory) {
    bytes32 intentHash = router.hashTypedIntentData(intentData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(mainWalletPrivateKey, intentHash);
    return abi.encodePacked(r, s, v);
  }

  function _getSWSignature(ActionData memory actionData) internal view returns (bytes memory) {
    bytes32 actionHash = router.hashTypedActionData(actionData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionWalletPrivateKey, actionHash);
    return abi.encodePacked(r, s, v);
  }

  function _getSwapCalldata(string memory chain, SwapRequest memory req)
    internal
    returns (address, bytes4, bytes memory, uint256)
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

    return (routerAddress, _getSelector(swapCallData), _removeSelector(swapCallData), value);
  }

  function _getSelector(bytes memory data) internal pure returns (bytes4) {
    bytes memory returnValue = new bytes(4);
    for (uint256 i = 0; i < 4; i++) {
      returnValue[i] = data[i];
    }

    return bytes4(returnValue);
  }

  function _removeSelector(bytes memory data) internal pure returns (bytes memory) {
    bytes memory returnValue = new bytes(data.length - 4);
    for (uint256 i = 4; i < data.length; i++) {
      returnValue[i - 4] = data[i];
    }
    return returnValue;
  }

  function _readSwapInputs() internal view returns (SwapInputs memory swapInputs) {
    string memory json = _getJsonString('swap-inputs');
    (swapInputs) = abi.decode(json.parseRaw(dotChainId), (SwapInputs));
  }

  function _readString(string memory key) internal view returns (string memory) {
    string memory json = _getJsonString(key);
    return json.readString(dotChainId);
  }

  function _toArray(address value) internal pure returns (address[] memory) {
    address[] memory array = new address[](1);
    array[0] = value;
    return array;
  }

  function _toArray(bytes4 value) internal pure returns (bytes4[] memory) {
    bytes4[] memory array = new bytes4[](1);
    array[0] = value;
    return array;
  }
}
