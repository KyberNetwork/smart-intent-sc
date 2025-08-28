// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/hooks/base/BaseStatefulHook.sol';

contract KSTimeBasedDCAHook is BaseStatefulHook {
  using TokenHelper for address;

  error ExceedNumSwaps(uint256 numSwaps, uint256 swapNo);
  error InvalidExecutionTime(uint256 startTime, uint256 endTime, uint256 currentTime);
  error InvalidTokenIn(address tokenIn, address actualTokenIn);
  error InvalidAmountIn(uint256 amountIn, uint256 actualAmountIn);
  error InvalidAmountOut(uint256 minAmountOut, uint256 maxAmountOut, uint256 actualAmountOut);
  error SwapAlreadyExecuted();

  /**
   * @notice Data structure for dca validation
   * @param dstToken The destination token
   * @param amountIn The amount of source token to be swapped, should be the same for all swaps
   * @param amountOutLimits The minimum and maximum amount of destination token to be received, should be the same for all swaps (minAmountOut 128bits, maxAmountOut 128bits)
   * @param executionParams The parameters for swaps validation (numSwaps 32bits, duration 32bits, startPeriod 32bits, firstTimestamp 32bits)
   * @param recipient The recipient of the destination token
   */
  struct DCAHookData {
    address dstToken;
    uint256 amountIn;
    uint256 amountOutLimits;
    uint256 executionParams;
    address recipient;
  }

  mapping(bytes32 => uint256) public latestSwap;

  constructor(address[] memory initialRouters) BaseStatefulHook(initialRouters) {}

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 1, InvalidTokenData());
    require(actionData.erc721Ids.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    ActionData calldata actionData
  )
    external
    override
    onlyWhitelistedRouter
    checkTokenLengths(actionData)
    returns (uint256[] memory fees, bytes memory beforeExecutionData)
  {
    DCAHookData memory dcaHookData = abi.decode(intentData.coreData.hookIntentData, (DCAHookData));

    uint256 swapNo = abi.decode(actionData.hookActionData, (uint256));
    uint32 numSwaps = uint32(dcaHookData.executionParams >> 96);

    if (swapNo >= numSwaps) {
      revert ExceedNumSwaps(numSwaps, swapNo);
    }

    //validate execution time
    if (uint96(dcaHookData.executionParams) != 0) {
      uint32 duration = uint32(dcaHookData.executionParams >> 64);
      uint32 startPeriod = uint32(dcaHookData.executionParams >> 32);
      uint32 firstTimestamp = uint32(dcaHookData.executionParams);

      uint256 startTime = firstTimestamp + duration * swapNo;
      uint256 endTime = startTime + startPeriod;

      if (block.timestamp < startTime || endTime < block.timestamp) {
        revert InvalidExecutionTime(startTime, endTime, uint32(block.timestamp));
      }
    }

    if (actionData.erc20Amounts[0] != dcaHookData.amountIn) {
      revert InvalidAmountIn(dcaHookData.amountIn, actionData.erc20Amounts[0]);
    }

    //validate this swap is not executed before
    swapNo++; //swapNo starts from 0, latestSwap starts from 1
    if (swapNo <= latestSwap[intentHash]) {
      revert SwapAlreadyExecuted();
    }
    latestSwap[intentHash] = swapNo;

    uint256 balanceBefore = dcaHookData.dstToken.balanceOf(dcaHookData.recipient);

    fees = new uint256[](actionData.erc20Ids.length);
    beforeExecutionData = abi.encode(balanceBefore);
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32,
    IntentData calldata intentData,
    bytes calldata beforeExecutionData,
    bytes calldata
  )
    external
    view
    override
    onlyWhitelistedRouter
    returns (address[] memory, uint256[] memory, uint256[] memory, address)
  {
    DCAHookData memory dcaHookData = abi.decode(intentData.coreData.hookIntentData, (DCAHookData));

    uint128 minAmountOut = uint128(dcaHookData.amountOutLimits >> 128);
    uint128 maxAmountOut = uint128(dcaHookData.amountOutLimits);

    uint256 balanceBefore = abi.decode(beforeExecutionData, (uint256));
    uint256 amountOut = dcaHookData.dstToken.balanceOf(dcaHookData.recipient) - balanceBefore;

    if (amountOut < minAmountOut || maxAmountOut < amountOut) {
      revert InvalidAmountOut(minAmountOut, maxAmountOut, amountOut);
    }
  }
}
