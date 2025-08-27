// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import 'src/hooks/base/BaseStatefulHook.sol';

contract KSPriceBasedDCAHook is BaseStatefulHook {
  using TokenHelper for address;

  error ExceedNumSwaps(uint256 numSwaps, uint256 swapNo);
  error InvalidAmountIn(uint256 amountIn, uint256 actualAmountIn);
  error InvalidAmountOut(uint256 minAmountOut, uint256 maxAmountOut, uint256 actualAmountOut);
  error SwapAlreadyExecuted();

  /**
   * @notice Data structure for dca hook
   * @param dstToken The destination token
   * @param amountIns
   * @param amountOutLimits
   * @param recipient
   */
  struct DCAHookData {
    address srcToken;
    address dstToken;
    uint256[] amountIns;
    uint256[] amountOutLimits;
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
    uint256 numSwaps = dcaHookData.amountOutLimits.length;

    if (swapNo >= numSwaps) {
      revert ExceedNumSwaps(numSwaps, swapNo);
    }

    if (actionData.erc20Amounts[0] != dcaHookData.amountIns[swapNo]) {
      revert InvalidAmountIn(dcaHookData.amountIns[swapNo], actionData.erc20Amounts[0]);
    }

    //validate this swap is not executed before
    swapNo++; //swapNo starts from 0, latestSwap starts from 1
    if (swapNo <= latestSwap[intentHash]) {
      revert SwapAlreadyExecuted();
    }
    latestSwap[intentHash] = swapNo;

    uint256 balanceBefore = dcaHookData.dstToken.balanceOf(dcaHookData.recipient);

    fees = new uint256[](actionData.erc20Ids.length);
    beforeExecutionData = abi.encode(--swapNo, balanceBefore);
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

    (uint256 swapNo, uint256 balanceBefore) = abi.decode(beforeExecutionData, (uint256, uint256));

    uint128 minAmountOut = uint128(dcaHookData.amountOutLimits[swapNo] >> 128);
    uint128 maxAmountOut = uint128(dcaHookData.amountOutLimits[swapNo]);

    uint256 amountOut = dcaHookData.dstToken.balanceOf(dcaHookData.recipient) - balanceBefore;

    if (amountOut < minAmountOut || maxAmountOut < amountOut) {
      revert InvalidAmountOut(minAmountOut, maxAmountOut, amountOut);
    }
  }
}
