// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

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

  function doNothing() external pure {}

  function removeUniswapV4(
    IPositionManager posManager,
    uint256 tokenId,
    address owner,
    address token0,
    address token1
  ) external {
    uint128 liquidity = posManager.getPositionLiquidity(tokenId);
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
    token0.safeTransfer(owner, token0.balanceOf(address(this)));
    token1.safeTransfer(owner, token1.balanceOf(address(this)));
  }

  fallback() external payable {}
}
