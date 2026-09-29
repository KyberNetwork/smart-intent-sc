// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'test/Base.t.sol';

import 'src/hooks/swap/KSConditionalSwapHook.sol';
import 'test/utils/MerkleUtils.sol';

import {toBoolAddress} from 'src/types/BoolAddress.sol';
import {OracleConfig, OracleLib, TokenOracle} from 'src/types/OracleConfig.sol';
import {toOracleSource} from 'src/types/OracleSource.sol';
import {PackedU128, toPackedU128} from 'src/types/PackedU128.sol';

abstract contract ConditionalSwapBaseTest is BaseTest {
  using SafeERC20 for IERC20;
  using TokenHelper for address;
  using ArraysHelper for *;
  using MerkleUtils for *;

  uint256 feeBefore;
  uint256 feeAfter;
  uint256 maxSrcFee;
  uint256 maxDstFee;

  uint256 swapAmount = 1_000_000_000;

  // Merkle commitment over the allowed swap legs, rebuilt by `_setUpLeaves` for each intent.
  bytes32 root;
  bytes32[] leaves;
  // Mirrors `leaves`, so helpers can re-encode the condition a proof is checked against.
  KSConditionalSwapHook.SwapCondition[] leafConditions;

  KSConditionalSwapHook conditionalSwapHook;

  function setUp() public virtual override {
    super.setUp();

    address[] memory routers = new address[](1);
    routers[0] = address(router);
    deal(tokenOut, address(mockActionContract), 1e30);
    deal(tokenIn, mainAddress, 1e30);

    conditionalSwapHook = new KSConditionalSwapHook(routers);
  }

  function _emptyLeg() internal pure returns (TokenOracle memory) {
    return TokenOracle(
      toBoolAddress(false, address(0)),
      toOracleSource(0, address(0)),
      toPackedU128(0, 0),
      abi.encode(bytes32(0))
    );
  }

  function _config(TokenOracle memory oracleIn, TokenOracle memory oracleOut, uint256 maxDeviation)
    internal
    pure
    returns (OracleConfig memory)
  {
    return _config(oracleIn, oracleOut, maxDeviation, _fullBand());
  }

  function _config(
    TokenOracle memory oracleIn,
    TokenOracle memory oracleOut,
    uint256 maxDeviation,
    PackedU128 oracleRatioLimits
  ) internal pure returns (OracleConfig memory) {
    return OracleConfig(oracleIn, oracleOut, oracleRatioLimits, maxDeviation);
  }

  function _directConfig(TokenOracle memory directOracle, uint256 maxDeviation)
    internal
    pure
    returns (OracleConfig memory)
  {
    return _config(directOracle, _emptyLeg(), maxDeviation);
  }

  function _noOracle() internal pure returns (OracleConfig memory) {
    return _config(_emptyLeg(), _emptyLeg(), 0);
  }

  /// @dev USD price band [price*(1-bpsBelow), price*(1+bpsAbove)], packed min 128 | max 128.
  function _band(uint256 price, uint256 bpsBelow, uint256 bpsAbove)
    internal
    pure
    returns (PackedU128)
  {
    uint256 lower = (price * (10_000 - bpsBelow)) / 10_000;
    uint256 upper = (price * (10_000 + bpsAbove)) / 10_000;
    return toPackedU128(lower, upper);
  }

  function _fullBand() internal pure returns (PackedU128) {
    return toPackedU128(0, type(uint128).max);
  }

  /// @dev Undo a 1e18 inversion to recover the raw adapter price that `priceLimits` bounds.
  function _inv(uint256 price) internal pure returns (uint256) {
    return 1e36 / price;
  }

  function _readReal(OracleConfig memory cfg)
    internal
    view
    returns (uint256 priceIn, uint256 priceOut, uint256 ratio)
  {
    return this.readReal(cfg);
  }

  function readReal(OracleConfig calldata cfg)
    external
    view
    returns (uint256 priceIn, uint256 priceOut, uint256 ratio)
  {
    return OracleLib.getPrices(cfg, tokenIn, tokenOut);
  }

  function _validateOracle(
    OracleConfig memory cfg,
    address tokenIn_,
    address tokenOut_,
    uint256 realizedPrice
  ) internal view returns (bool) {
    try this.validateOracle(cfg, tokenIn_, tokenOut_, realizedPrice) returns (bool valid) {
      return valid;
    } catch {
      return false;
    }
  }

  function validateOracle(
    OracleConfig calldata cfg,
    address tokenIn_,
    address tokenOut_,
    uint256 realizedPrice
  ) external view returns (bool) {
    OracleLib.validate(cfg, tokenIn_, tokenOut_, realizedPrice);
    return true;
  }

  function _oracleCondition(OracleConfig memory oracle)
    internal
    pure
    returns (KSConditionalSwapHook.SwapCondition memory)
  {
    return KSConditionalSwapHook.SwapCondition({
      swapLimit: 4,
      timeLimits: toPackedU128(0, type(uint128).max),
      amountInLimits: toPackedU128(0, type(uint128).max),
      maxFees: toPackedU128(0, type(uint128).max),
      priceLimits: toPackedU128(0, type(uint128).max),
      oracle: oracle
    });
  }

  function _single(OracleConfig memory oracle)
    internal
    pure
    returns (KSConditionalSwapHook.SwapCondition[] memory conditions)
  {
    conditions = new KSConditionalSwapHook.SwapCondition[](1);
    conditions[0] = _oracleCondition(oracle);
  }

  function _timeCondition(PackedU128 timeLimits)
    internal
    view
    returns (KSConditionalSwapHook.SwapCondition memory)
  {
    return KSConditionalSwapHook.SwapCondition({
      swapLimit: 1,
      timeLimits: timeLimits,
      amountInLimits: toPackedU128(swapAmount, swapAmount),
      maxFees: toPackedU128(0, type(uint128).max),
      priceLimits: toPackedU128(0, type(uint128).max),
      oracle: _noOracle()
    });
  }

  /// @dev amountOut that yields a realized price of `realizedPrice` for amountIn == swapAmount.
  function _amountOutFor(uint256 realizedPrice) internal view returns (uint256) {
    return (realizedPrice * swapAmount) / 1e18;
  }

  function _realizedPriceFor(uint256 ratio, uint256 amountIn) internal pure returns (uint256) {
    uint256 amountOut = (ratio * amountIn) / 1e18;
    return (amountOut * 1e18) / amountIn;
  }

  function _mockSwapAction() internal view returns (ActionData memory actionData) {
    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](1);
    tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});
    actionData = _getActionData(
      tokenData,
      abi.encode(
        tokenIn,
        tokenOut,
        swapAmount,
        1000,
        feeAfter == 0 ? mainAddress : address(router),
        mainAddress
      ),
      true
    );
  }

  function _buildIntentAndAction(
    KSConditionalSwapHook.SwapCondition[] memory conditions,
    uint256 amountOut
  ) internal returns (IntentData memory intentData, ActionData memory actionData) {
    intentData = _buildIntent(conditions);
    actionData = _buildMockSwapAction(amountOut);
  }

  function _buildIntent(KSConditionalSwapHook.SwapCondition[] memory conditions)
    internal
    returns (IntentData memory intentData)
  {
    {
      uint256 tmp = swapAmount;
      swapAmount = type(uint256).max;
      intentData = _getIntentData(0, type(uint128).max, conditions);
      _setUpMainAddress(intentData, false);
      swapAmount = tmp;
    }
  }

  function _buildMockSwapAction(uint256 amountOut)
    internal
    view
    returns (ActionData memory actionData)
  {
    TokenData memory tokenData;
    tokenData.erc20Data = new ERC20Data[](1);
    tokenData.erc20Data[0] = ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});

    actionData = _getActionData(
      tokenData,
      abi.encode(tokenIn, tokenOut, swapAmount, amountOut, mainAddress, mainAddress),
      true
    );
    actionData.hookActionData = _hookActionData(0, 0, 0);
  }

  function _expectSwapOk(uint256 mode, OracleConfig memory cfg, uint256 amountOut) internal {
    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), amountOut);
    uint256 balBefore = IERC20(tokenOut).balanceOf(mainAddress);
    _executeSwap(mode, intentData, actionData);
    assertGt(IERC20(tokenOut).balanceOf(mainAddress), balBefore);
  }

  function _expectSwapRevert(uint256 mode, OracleConfig memory cfg, uint256 amountOut) internal {
    (IntentData memory intentData, ActionData memory actionData) =
      _buildIntentAndAction(_single(cfg), amountOut);
    (address caller, bytes memory dk, bytes memory gd) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    vm.expectRevert();
    router.execute(intentData, dk, guardian, gd, actionData);
  }

  function _executeSwap(uint256 mode, IntentData memory intentData, ActionData memory actionData)
    internal
  {
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    vm.stopPrank();
  }

  function _revertSelector(bytes memory revertData) internal pure returns (bytes4 selector) {
    assertGe(revertData.length, 4);
    assembly ('memory-safe') {
      selector := mload(add(revertData, 0x20))
    }
  }

  function _expectExecuteRevert(
    uint256 mode,
    IntentData memory intentData,
    ActionData memory actionData,
    bytes4 selector
  ) internal {
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    vm.expectPartialRevert(selector);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    vm.stopPrank();
  }

  function _expectExecuteRevert(
    uint256 mode,
    IntentData memory intentData,
    ActionData memory actionData,
    bytes memory revertData
  ) internal {
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);
    vm.startPrank(caller);
    vm.expectRevert(revertData);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    vm.stopPrank();
  }

  function _swap(
    uint256 mode,
    IntentData memory intentData,
    ActionData memory actionData,
    uint256 swapCount,
    uint256 index
  ) internal {
    actionData.hookActionData = _hookActionData(index);
    (address caller, bytes memory dkSignature, bytes memory gdSignature) =
      _getCallerAndSignatures(mode, intentData, actionData);
    bytes32 hash = router.hashTypedIntentData(intentData);

    uint256 balanceBefore = tokenOut.balanceOf(mainAddress);

    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, index), swapCount);
    vm.startPrank(caller);
    router.execute(intentData, dkSignature, guardian, gdSignature, actionData);
    vm.stopPrank();
    assertEq(conditionalSwapHook.getSwapExecutionCount(hash, index), swapCount + 1);

    assertGt(tokenOut.balanceOf(mainAddress), balanceBefore);
  }

  /**
   * @dev Commits `conditions` to a merkle tree, one leaf per condition, keyed by its index and the
   *      tokenIn/tokenOut pair. Mirrors the leaf hashing the hook performs in `beforeExecution`.
   */
  function _setUpLeaves(KSConditionalSwapHook.SwapCondition[] memory conditions)
    internal
    returns (bytes32[] memory, bytes32)
  {
    uint256[] memory leafIndexes = new uint256[](conditions.length);
    for (uint256 i = 0; i < conditions.length; i++) {
      leafIndexes[i] = i;
    }
    return _setUpLeaves(leafIndexes, conditions);
  }

  /// @dev As above, but with leaf indexes that need not match the position in the tree.
  function _setUpLeaves(
    uint256[] memory leafIndexes,
    KSConditionalSwapHook.SwapCondition[] memory conditions
  ) internal returns (bytes32[] memory, bytes32) {
    leaves = new bytes32[](conditions.length);
    delete leafConditions;

    for (uint256 i = 0; i < conditions.length; i++) {
      leaves[i] = keccak256(abi.encode(leafIndexes[i], tokenIn, tokenOut, conditions[i]));
      leafConditions.push(conditions[i]);
    }

    root = leaves.getRoot();

    return (leaves, root);
  }

  /// @dev hookActionData proving `leafIndex` against the current root, with the current fee rates.
  function _hookActionData(uint256 leafIndex) internal view returns (bytes memory) {
    return _hookActionData(leafIndex, feeBefore, feeAfter);
  }

  function _hookActionData(uint256 leafIndex, uint256 srcFee, uint256 dstFee)
    internal
    view
    returns (bytes memory)
  {
    bytes32[] memory memLeaves = leaves;
    return abi.encode(
      MerkleUtils.getProof(memLeaves, leafIndex),
      leafIndex,
      tokenOut,
      toPackedU128(srcFee, dstFee),
      leafConditions[leafIndex]
    );
  }

  function _getActionData(TokenData memory tokenData, bytes memory actionCalldata, bool swapViaMock)
    internal
    view
    returns (ActionData memory actionData)
  {
    // Assigned field by field: a struct literal keeps every field on the stack at once, which
    // overflows it once via-IR inlines this into callers that also hold an IntentData.
    actionData.feeInfo.protocolRecipient = protocolRecipient;
    actionData.feeInfo.partnerFeeConfigs = new FeeConfig[][](1);
    actionData.feeInfo.partnerFeeConfigs[0] = _buildPartnersConfigs(
      PartnersFeeConfigBuildParams({
        feeModes: [false].toMemoryArray(),
        partnerFees: [uint24(1e6)].toMemoryArray(),
        partnerRecipients: [partnerRecipient].toMemoryArray()
      })
    );

    actionData.erc20Ids = [uint256(0)].toMemoryArray();
    actionData.erc20Amounts = [tokenData.erc20Data[0].amount].toMemoryArray();
    actionData.approvalFlags = (1 << (tokenData.erc20Data.length + tokenData.erc721Data.length)) - 1;
    actionData.actionSelectorId = swapViaMock ? 0 : 1;
    if (swapViaMock && actionCalldata.length == 0) {
      actionCalldata = abi.encode(
        tokenIn,
        tokenOut,
        swapAmount,
        1000,
        feeAfter == 0 ? mainAddress : address(router),
        mainAddress
      );
    }
    actionData.actionCalldata = actionCalldata;
    actionData.hookActionData = _hookActionData(0);
    actionData.deadline = vm.getBlockTimestamp() + 1 days;
  }

  function _getIntentData(
    uint256 min,
    uint256 max,
    KSConditionalSwapHook.SwapCondition[] memory swapConditions
  ) internal returns (IntentData memory intentData) {
    if (swapConditions.length == 0) {
      swapConditions = new KSConditionalSwapHook.SwapCondition[](1);
      swapConditions[0] = KSConditionalSwapHook.SwapCondition({
        swapLimit: 1,
        timeLimits: toPackedU128(vm.getBlockTimestamp(), vm.getBlockTimestamp() + 1 days),
        amountInLimits: toPackedU128(min, max),
        maxFees: toPackedU128(maxSrcFee, maxDstFee),
        priceLimits: toPackedU128(0, type(uint128).max),
        oracle: _noOracle()
      });
    }

    _setUpLeaves(swapConditions);

    return _getIntentDataForRoot();
  }

  /// @dev Builds an intent committing to the root `_setUpLeaves` last produced.
  function _getIntentDataForRoot() internal view returns (IntentData memory intentData) {
    KSConditionalSwapHook.SwapHookData memory hookData;
    hookData.root = root;
    hookData.recipient = mainAddress;

    intentData.coreData.mainAddress = mainAddress;
    intentData.coreData.signatureVerifier = address(0);
    intentData.coreData.delegatedKey = delegatedPublicKey;
    intentData.coreData.actionContracts =
      [address(mockActionContract), address(swapRouter)].toMemoryArray();
    intentData.coreData.actionSelectors =
      [MockActionContract.swap.selector, IKSSwapRouterV2.swap.selector].toMemoryArray();
    intentData.coreData.hook = address(conditionalSwapHook);
    intentData.coreData.hookIntentData = abi.encode(hookData);

    intentData.tokenData.erc20Data = new ERC20Data[](1);
    intentData.tokenData.erc20Data[0] =
      ERC20Data({token: tokenIn, amount: swapAmount, permitData: ''});
  }

  function _setUpMainAddress(IntentData memory intentData, bool withSignedIntent) internal {
    vm.startPrank(mainAddress);
    IERC20(tokenIn).safeIncreaseAllowance(address(router), type(uint256).max);
    if (!withSignedIntent) {
      router.delegate(intentData);
    }
    vm.stopPrank();
  }

  function _adjustRecipient(bytes memory data) internal view returns (bytes memory) {
    IKSSwapRouterV2.SwapExecutionParams memory params =
      abi.decode(data, (IKSSwapRouterV2.SwapExecutionParams));

    params.desc.dstReceiver = feeAfter == 0 ? mainAddress : address(router);

    return abi.encode(params);
  }
}
