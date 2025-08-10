// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {console} from 'forge-std/console.sol';
import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import 'src/interfaces/IWETH.sol';

import {ICLPositionManager} from 'src/interfaces/pancakev4/ICLPositionManager.sol';
import 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';
import {StateLibrary} from 'src/libraries/uniswapv4/StateLibrary.sol';

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

  event Transferred(uint256 amount0, uint256 amount1);

  uint256 constant DECREASE_LIQUIDITY = 0x01;
  uint256 constant TAKE_PAIR = 0x11;
  uint256 constant NOT_TRANSFER = uint256(keccak256('NOT_TRANSFER'));

  function execute(bytes calldata) external {}

  struct RemoveUniswapV4Params {
    IPositionManager posManager;
    uint256 tokenId;
    address admin;
    address nftOwner;
    address token0;
    address token1;
    uint256 liquidity;
    uint256 transferPercent;
    bool wrapOrUnwrap;
    address weth;
    bool takeFees;
  }

  function removeUniswapV4(RemoveUniswapV4Params memory params) external {
    (uint256 amount0, uint256 amount1, uint256 unclaimedFee0, uint256 unclaimedFee1) = params
      .posManager
      .poolManager().computePositionValues(params.posManager, params.tokenId, params.liquidity);

    (PoolKey memory poolKey,) = params.posManager.getPoolAndPositionInfo(params.tokenId);
    bytes memory actions = new bytes(2);
    bytes[] memory univ4params = new bytes[](2);
    actions[0] = bytes1(uint8(DECREASE_LIQUIDITY));
    univ4params[0] = abi.encode(params.tokenId, params.liquidity, 0, 0, '');
    actions[1] = bytes1(uint8(TAKE_PAIR));
    univ4params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
    params.posManager.modifyLiquidities(abi.encode(actions, univ4params), type(uint256).max);
    if (params.admin != address(0)) {
      params.posManager.transferFrom(msg.sender, params.nftOwner, params.tokenId);
    }

    if (params.transferPercent == NOT_TRANSFER) {
      // not transfer back to admin
      return;
    }

    if (params.wrapOrUnwrap) {
      if (params.token0 == TokenHelper.NATIVE_ADDRESS) {
        IWETH(params.weth).deposit{value: amount0 + unclaimedFee0}();
        params.token0 = params.weth;
      } else if (params.token0 == params.weth) {
        IWETH(params.weth).withdraw(amount0 + unclaimedFee0);
        params.token0 = TokenHelper.NATIVE_ADDRESS;
      }

      if (params.token1 == TokenHelper.NATIVE_ADDRESS) {
        IWETH(params.weth).deposit{value: amount1 + unclaimedFee1}();
        params.token1 = params.weth;
      } else if (params.token1 == params.weth) {
        IWETH(params.weth).withdraw(amount1 + unclaimedFee1);
        params.token1 = TokenHelper.NATIVE_ADDRESS;
      }
    }

    uint256 amount0Transfer = amount0 * params.transferPercent / 1e6;
    uint256 amount1Transfer = amount1 * params.transferPercent / 1e6;

    if (!params.takeFees) {
      amount0Transfer += unclaimedFee0;
      amount1Transfer += unclaimedFee1;
    }

    params.token0.safeTransfer(params.admin, amount0Transfer);
    params.token1.safeTransfer(params.admin, amount1Transfer);
  }

  function removePancakeV4CL(
    ICLPositionManager pm,
    uint256 tokenId,
    address owner,
    address router,
    address token0,
    address token1,
    uint256 liquidity,
    uint256 transferPercent,
    bool wrapOrUnwrap,
    address weth,
    bool takeFees,
    uint256[2] memory amounts,
    uint256[2] memory fees
  ) external {
    uint256[2] memory balancesBefore = [token0.selfBalance(), token1.selfBalance()];

    bytes memory actions = new bytes(2);
    bytes[] memory pancakeParams = new bytes[](2);
    actions[0] = bytes1(uint8(DECREASE_LIQUIDITY));
    pancakeParams[0] = abi.encode(tokenId, liquidity, 0, 0, '');
    actions[1] = bytes1(uint8(TAKE_PAIR));
    pancakeParams[1] = abi.encode(
      token0 == TokenHelper.NATIVE_ADDRESS ? address(0) : token0,
      token1 == TokenHelper.NATIVE_ADDRESS ? address(0) : token1,
      address(this)
    );
    pm.modifyLiquidities(abi.encode(actions, pancakeParams), type(uint256).max);
    if (owner != address(0)) {
      pm.transferFrom(msg.sender, owner, tokenId);
    }

    uint256[2] memory received =
      [token0.selfBalance() - balancesBefore[0], token1.selfBalance() - balancesBefore[1]];

    require(received[0] == amounts[0] + fees[0], 'Invalid amount0');
    require(received[1] == amounts[1] + fees[1], 'Invalid amount1');

    if (transferPercent == NOT_TRANSFER) {
      // not transfer back to router
      return;
    }

    if (wrapOrUnwrap) {
      if (token0 == TokenHelper.NATIVE_ADDRESS) {
        IWETH(weth).deposit{value: received[0]}();
        token0 = weth;
      } else if (token0 == weth) {
        IWETH(weth).withdraw(received[0]);
        token0 = TokenHelper.NATIVE_ADDRESS;
      }

      if (token1 == TokenHelper.NATIVE_ADDRESS) {
        IWETH(weth).deposit{value: received[1]}();
        token1 = weth;
      } else if (token1 == weth) {
        IWETH(weth).withdraw(received[1]);
        token1 = TokenHelper.NATIVE_ADDRESS;
      }
    }

    uint256 amount0Transfer = amounts[0] * transferPercent / 1e6;
    uint256 amount1Transfer = amounts[1] * transferPercent / 1e6;

    if (!takeFees) {
      amount0Transfer += fees[0];
      amount1Transfer += fees[1];
    }

    token0.safeTransfer(router, amount0Transfer);
    token1.safeTransfer(router, amount1Transfer);
  }

  function removeUniswapV3(
    IUniswapV3PM pm,
    uint256 tokenId,
    address owner,
    address router,
    address token0,
    address token1,
    uint256 liquidity,
    uint256 transferPercent,
    bool wrapOrUnwrap,
    address weth,
    bool takeFees,
    uint256[2] memory amounts,
    uint256[2] memory fees
  ) external {
    if (liquidity > 0) {
      pm.decreaseLiquidity(
        IUniswapV3PM.DecreaseLiquidityParams({
          tokenId: tokenId,
          liquidity: uint128(liquidity),
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp + 1 days
        })
      );
    }

    uint256[2] memory balancesBefore = [token0.selfBalance(), token1.selfBalance()];

    pm.collect(
      IUniswapV3PM.CollectParams({
        tokenId: tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
    if (owner != address(0)) {
      pm.transferFrom(msg.sender, owner, tokenId);
    }

    if (transferPercent == NOT_TRANSFER) {
      // not transfer back to owner
      return;
    }

    uint256[2] memory received =
      [token0.selfBalance() - balancesBefore[0], token1.selfBalance() - balancesBefore[1]];

    require(received[0] == amounts[0] + fees[0], 'Invalid amount0');
    require(received[1] == amounts[1] + fees[1], 'Invalid amount1');

    if (!takeFees) {
      amounts[0] += fees[0];
      amounts[1] += fees[1];
    }

    if (wrapOrUnwrap) {
      if (token0 == weth) {
        IWETH(weth).withdraw(amounts[0]);
        token0 = TokenHelper.NATIVE_ADDRESS;
      }

      if (token1 == weth) {
        IWETH(weth).withdraw(amounts[1]);
        token1 = TokenHelper.NATIVE_ADDRESS;
      }
    }

    token0.safeTransfer(router, amounts[0] * transferPercent / 1e6);
    token1.safeTransfer(router, amounts[1] * transferPercent / 1e6);

    emit Transferred(amounts[0] * transferPercent / 1e6, amounts[1] * transferPercent / 1e6);
  }

  fallback() external payable {}

  receive() external payable {}
}
