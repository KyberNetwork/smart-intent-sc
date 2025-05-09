// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from '@openzeppelin/contracts/interfaces/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract MockDex {
  using SafeERC20 for IERC20;

  uint256 amountOut;
  uint256 cachedBalance;
  bool isFirstPool;

  function setFirstPool(bool val) external {
    isFirstPool = val;
  }

  function setAmountOut(uint256 val) external {
    amountOut = val;
  }

  function cacheBalance(uint256 val) external {
    cachedBalance = val;
  }

  function mockSwap(address tokenIn, address tokenOut, address recipient, uint256 amountIn)
    external
    returns (uint256 _amountOut)
  {
    recipient = recipient == address(0) ? msg.sender : recipient;
    if (!isFirstPool) {
      IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    } else {
      require(
        IERC20(tokenIn).balanceOf(address(this)) - cachedBalance >= amountIn,
        'MockDex: not enough token in'
      );
    }
    _amountOut = amountOut;
    IERC20(tokenOut).safeTransfer(recipient, _amountOut);
  }
}
