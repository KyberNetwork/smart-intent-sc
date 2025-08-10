// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import 'src/hooks/base/BaseTickBasedRemoveLiquidityHook.sol';
import 'src/libraries/uniswapv4/StateLibrary.sol';

contract KSRemoveLiquidityUniswapV4Hook is BaseTickBasedRemoveLiquidityHook {
  using StateLibrary for IPoolManager;
  using TokenHelper for address;

  /**
   * @notice Parameters used for remove liquidity validation of a uniswap v4 position
   * @param poolManager The pool manager contract
   * @param removeLiqParams The params used to remove liquidity
   * @param outputParams The params used to validate output after execution
   */
  struct UniswapV4Params {
    IPoolManager poolManager;
    RemoveLiquidityParams removeLiqParams;
    OutputValidationParams outputParams;
  }

  constructor(address _weth) BaseTickBasedRemoveLiquidityHook(_weth) {}

  function _validateBeforeExecution(
    IntentCoreData calldata coreData,
    ActionData calldata actionData
  ) internal view override returns (bytes memory beforeExecutionData) {
    UniswapV4Params memory uniswapV4;

    RemoveLiquidityHookData calldata validationData = _decodeHookData(coreData.hookIntentData);

    _cacheValidationData(uniswapV4, validationData, actionData.hookActionData);

    _validateConditions(
      validationData.nodes[uniswapV4.removeLiqParams.index],
      uniswapV4.removeLiqParams.positionInfo.feesGenerated[0],
      uniswapV4.removeLiqParams.positionInfo.feesGenerated[1],
      uniswapV4.removeLiqParams.sqrtPriceX96
    );

    beforeExecutionData = abi.encode(uniswapV4.removeLiqParams, uniswapV4.outputParams);
  }

  function _cacheValidationData(
    UniswapV4Params memory uniswapV4,
    RemoveLiquidityHookData calldata validationData,
    bytes calldata hookActionData
  ) internal view {
    OutputValidationParams memory outputParams = uniswapV4.outputParams;
    RemoveLiquidityParams memory removeLiqParams = uniswapV4.removeLiqParams;

    _cacheBaseData(validationData, hookActionData, removeLiqParams, outputParams);

    IPositionManager positionManager = IPositionManager(removeLiqParams.positionInfo.nftAddress);
    uint256 nftId = removeLiqParams.positionInfo.nftId;
    uniswapV4.poolManager = positionManager.poolManager();

    (PoolKey memory poolKey,) = positionManager.getPoolAndPositionInfo(nftId);
    (removeLiqParams.sqrtPriceX96,,,) =
      uniswapV4.poolManager.getSlot0(StateLibrary.getPoolId(poolKey));
    removeLiqParams.positionInfo.liquidity = _getPositionLiquidity(address(positionManager), nftId);

    outputParams.tokens = [_toNative(poolKey.currency0), _toNative(poolKey.currency1)];
    if (removeLiqParams.wrapOrUnwrap) {
      outputParams.tokens =
        [_adjustToken(outputParams.tokens[0]), _adjustToken(outputParams.tokens[1])];
    }

    (outputParams.balancesBefore[0], outputParams.balancesBefore[1]) =
      _recordRouterBalances(msg.sender, outputParams.tokens);
    _computePositionValues(uniswapV4);
  }

  function _computePositionValues(UniswapV4Params memory uniswapV4) internal view {
    (
      uniswapV4.removeLiqParams.positionInfo.amounts[0],
      uniswapV4.removeLiqParams.positionInfo.amounts[1],
      uniswapV4.removeLiqParams.positionInfo.unclaimedFees[0],
      uniswapV4.removeLiqParams.positionInfo.unclaimedFees[1]
    ) = uniswapV4.poolManager.computePositionValues(
      IPositionManager(uniswapV4.removeLiqParams.positionInfo.nftAddress),
      uniswapV4.removeLiqParams.positionInfo.nftId,
      uniswapV4.removeLiqParams.liquidityToRemove
    );
  }
}
