// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {console} from 'forge-std/console.sol';
import 'ks-common-sc/libraries/token/TokenHelper.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';

struct UniswapV4Data {
  address posManager;
  uint256 tokenId;
  uint128 liquidity;
  uint128[2] minAmounts;
  address owner;
  bytes hookData;
}

contract MockActionContract {
  using TokenHelper for address;

  uint256 constant DECREASE_LIQUIDITY = 0x01;
  uint256 constant TAKE_PAIR = 0x11;
  uint256 constant MAGIC_NUMBER_NOT_TRANSFER = uint256(keccak256('NOT_TRANSFER'));
  uint256 constant MAGIC_NUMBER_TRANSFER_99PERCENT = uint256(keccak256('99PERCENT'));
  uint256 constant MAGIC_NUMBER_TRANSFER_98PERCENT = uint256(keccak256('98PERCENT'));

  function doNothing() external pure {}

  function removeUniswapV4(
    IPositionManager posManager,
    uint256 tokenId,
    address owner,
    address token0,
    address token1,
    uint256 liquidity,
    uint256 magicNumber
  ) external {
    (PoolKey memory poolKey,) = posManager.getPoolAndPositionInfo(tokenId);
    bytes memory actions = new bytes(2);
    bytes[] memory params = new bytes[](2);
    actions[0] = bytes1(uint8(DECREASE_LIQUIDITY));
    params[0] = abi.encode(tokenId, liquidity, 0, 0, '');
    actions[1] = bytes1(uint8(TAKE_PAIR));
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
    posManager.modifyLiquidities(abi.encode(actions, params), type(uint256).max);
    if (owner != address(0)) {
      posManager.transferFrom(msg.sender, owner, tokenId);
    }

    uint256 amount0 = token0.balanceOf(address(this));
    uint256 amount1 = token1.balanceOf(address(this));
    console.log('amount0', amount0);
    console.log('amount1', amount1);

    if (magicNumber == MAGIC_NUMBER_NOT_TRANSFER) {
      // not transfer back to owner
      return;
    }

    if (magicNumber == MAGIC_NUMBER_TRANSFER_99PERCENT) {
      token0.safeTransfer(owner, amount0 * 0.991e18 / 1e18);
      token1.safeTransfer(owner, amount1 * 0.991e18 / 1e18);
      return;
    }

    if (magicNumber == MAGIC_NUMBER_TRANSFER_98PERCENT) {
      token0.safeTransfer(owner, amount0 * 0.98e18 / 1e18);
      token1.safeTransfer(owner, amount1 * 0.98e18 / 1e18);
      return;
    }

    token0.safeTransfer(owner, amount0);
    token1.safeTransfer(owner, amount1);
  }

  fallback() external payable {}
}
