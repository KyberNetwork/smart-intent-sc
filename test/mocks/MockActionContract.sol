// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {console} from 'forge-std/console.sol';
import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import 'src/interfaces/IWETH.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';
import 'src/libraries/uniswapv4/StateLibrary.sol';

struct UniswapV4Data {
  address posManager;
  uint256 tokenId;
  uint128 liquidity;
  uint128[2] minAmounts;
  address admin;
  bytes hookData;
}

contract MockActionContract {
  using TokenHelper for address;
  using StateLibrary for IPoolManager;

  uint256 constant DECREASE_LIQUIDITY = 0x01;
  uint256 constant TAKE_PAIR = 0x11;
  uint256 constant NOT_TRANSFER = uint256(keccak256('NOT_TRANSFER'));

  function execute(bytes calldata data) external {
    if (data.length > 0) {
      (address token, address router) = abi.decode(data, (address, address));
      uint256 amount = token.balanceOf(msg.sender);
      token.safeTransferFrom(msg.sender, router, amount);
    }
  }

  function removeUniswapV4(
    IPositionManager posManager,
    uint256 tokenId,
    address admin,
    address token0,
    address token1,
    uint256 liquidity,
    uint256 transferPercent,
    bool wrapOrUnwrap,
    address weth,
    bool takeFees
  ) external {
    (uint256 amount0, uint256 amount1, uint256 unclaimedFee0, uint256 unclaimedFee1) =
      posManager.poolManager().computePositionValues(posManager, tokenId, liquidity);

    (PoolKey memory poolKey,) = posManager.getPoolAndPositionInfo(tokenId);
    bytes memory actions = new bytes(2);
    bytes[] memory params = new bytes[](2);
    actions[0] = bytes1(uint8(DECREASE_LIQUIDITY));
    params[0] = abi.encode(tokenId, liquidity, 0, 0, '');
    actions[1] = bytes1(uint8(TAKE_PAIR));
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
    posManager.modifyLiquidities(abi.encode(actions, params), type(uint256).max);
    if (admin != address(0)) {
      posManager.transferFrom(msg.sender, admin, tokenId);
    }

    if (transferPercent == NOT_TRANSFER) {
      // not transfer back to admin
      return;
    }

    if (wrapOrUnwrap) {
      if (token0 == TokenHelper.NATIVE_ADDRESS) {
        IWETH(weth).deposit{value: amount0 + unclaimedFee0}();
        token0 = weth;
      } else if (token0 == weth) {
        IWETH(weth).withdraw(amount0 + unclaimedFee0);
        token0 = TokenHelper.NATIVE_ADDRESS;
      }

      if (token1 == TokenHelper.NATIVE_ADDRESS) {
        IWETH(weth).deposit{value: amount1 + unclaimedFee1}();
        token1 = weth;
      } else if (token1 == weth) {
        IWETH(weth).withdraw(amount1 + unclaimedFee1);
        token1 = TokenHelper.NATIVE_ADDRESS;
      }
    }

    uint256 amount0Transfer = amount0 * transferPercent / 1e6;
    uint256 amount1Transfer = amount1 * transferPercent / 1e6;

    if (!takeFees) {
      amount0Transfer += unclaimedFee0;
      amount1Transfer += unclaimedFee1;
    }

    token0.safeTransfer(admin, amount0Transfer);
    token1.safeTransfer(admin, amount1Transfer);
  }

  fallback() external payable {}

  receive() external payable {}
}
