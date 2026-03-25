// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {IAllowanceTransfer} from 'ks-common-sc/src/interfaces/IAllowanceTransfer.sol';
import 'src/interfaces/IWETH.sol';

import {ICLPositionManager} from 'src/interfaces/pancakev4/ICLPositionManager.sol';
import {
  Actions as PancakeActions,
  PoolId,
  PoolKey as PancakePoolKey
} from 'src/interfaces/pancakev4/Types.sol';
import {IUniswapV3PM} from 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import {IPoolManager} from 'src/interfaces/uniswapv4/IPoolManager.sol';
import {IPositionManager} from 'src/interfaces/uniswapv4/IPositionManager.sol';
import {PoolKey} from 'src/interfaces/uniswapv4/Types.sol';
import {Actions} from 'src/interfaces/uniswapv4/Types.sol';
import {LiquidityAmounts} from 'src/libraries/uniswapv4/LiquidityAmounts.sol';
import {StateLibrary} from 'src/libraries/uniswapv4/StateLibrary.sol';
import {TickMath} from 'src/libraries/uniswapv4/TickMath.sol';

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

  address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
  address internal constant PERMIT2_BSC = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;

  function execute(bytes calldata data) external {
    if (data.length > 0) {
      (address token, address router) = abi.decode(data, (address, address));
      uint256 amount = token.balanceOf(msg.sender);
      token.safeTransferFrom(msg.sender, router, amount);
    }
  }

  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    address recipient,
    address mainAddress
  ) external {
    uint256 remainingAmountIn = tokenIn.balanceOf(msg.sender) - amountIn;
    tokenIn.safeTransferFrom(msg.sender, address(this), tokenIn.balanceOf(msg.sender));
    tokenOut.safeTransfer(recipient, amountOut);
    tokenIn.safeTransfer(mainAddress, remainingAmountIn);
  }

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
    (uint256 amount0, uint256 amount1, uint256 unclaimedFee0, uint256 unclaimedFee1) = params.posManager
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

  struct RemovePancakeV4CLParams {
    ICLPositionManager pm;
    uint256 tokenId;
    address owner;
    address router;
    address token0;
    address token1;
    uint256 liquidity;
    uint256 transferPercent;
    bool wrapOrUnwrap;
    address weth;
    bool takeFees;
    uint256[2] amounts;
    uint256[2] fees;
  }

  function removePancakeV4CL(RemovePancakeV4CLParams memory params) external {
    uint256[2] memory balancesBefore = [params.token0.selfBalance(), params.token1.selfBalance()];

    bytes memory actions = new bytes(2);
    bytes[] memory pancakeParams = new bytes[](2);
    actions[0] = bytes1(uint8(DECREASE_LIQUIDITY));
    pancakeParams[0] = abi.encode(params.tokenId, params.liquidity, 0, 0, '');
    actions[1] = bytes1(uint8(TAKE_PAIR));
    pancakeParams[1] = abi.encode(
      params.token0 == TokenHelper.NATIVE_ADDRESS ? address(0) : params.token0,
      params.token1 == TokenHelper.NATIVE_ADDRESS ? address(0) : params.token1,
      address(this)
    );
    params.pm.modifyLiquidities(abi.encode(actions, pancakeParams), type(uint256).max);
    if (params.owner != address(0)) {
      params.pm.transferFrom(msg.sender, params.owner, params.tokenId);
    }

    uint256[2] memory received = [
      params.token0.selfBalance() - balancesBefore[0],
      params.token1.selfBalance() - balancesBefore[1]
    ];

    require(received[0] == params.amounts[0] + params.fees[0], 'Invalid amount0');
    require(received[1] == params.amounts[1] + params.fees[1], 'Invalid amount1');

    if (params.transferPercent == NOT_TRANSFER) {
      // not transfer back to router
      return;
    }

    if (params.wrapOrUnwrap) {
      if (params.token0 == TokenHelper.NATIVE_ADDRESS) {
        IWETH(params.weth).deposit{value: received[0]}();
        params.token0 = params.weth;
      } else if (params.token0 == params.weth) {
        IWETH(params.weth).withdraw(received[0]);
        params.token0 = TokenHelper.NATIVE_ADDRESS;
      }

      if (params.token1 == TokenHelper.NATIVE_ADDRESS) {
        IWETH(params.weth).deposit{value: received[1]}();
        params.token1 = params.weth;
      } else if (params.token1 == params.weth) {
        IWETH(params.weth).withdraw(received[1]);
        params.token1 = TokenHelper.NATIVE_ADDRESS;
      }
    }

    uint256 amount0Transfer = params.amounts[0] * params.transferPercent / 1e6;
    uint256 amount1Transfer = params.amounts[1] * params.transferPercent / 1e6;

    if (!params.takeFees) {
      amount0Transfer += params.fees[0];
      amount1Transfer += params.fees[1];
    }

    params.token0.safeTransfer(params.router, amount0Transfer);
    params.token1.safeTransfer(params.router, amount1Transfer);
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

  // ─── Zap-migrate mocks ────────────────────────────────────────────────────

  struct ZapMigrateUniswapV3Params {
    IUniswapV3PM pm;
    uint256 oldTokenId;
    int24 newTickLower;
    int24 newTickUpper;
    address router;
    address mainAddress;
    uint256[] amountDesireds;
    uint256[] fees;
  }

  function zapMigrateUniswapV3(ZapMigrateUniswapV3Params memory params) external {
    (,, address token0, address token1, uint24 fee,,, uint128 liquidity,,,,) =
      params.pm.positions(params.oldTokenId);

    if (liquidity > 0) {
      params.pm
        .decreaseLiquidity(
          IUniswapV3PM.DecreaseLiquidityParams({
            tokenId: params.oldTokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 1 days
          })
        );
    }

    uint256 balance0Before = IERC20(token0).balanceOf(address(this));
    uint256 balance1Before = IERC20(token1).balanceOf(address(this));

    params.pm
      .collect(
        IUniswapV3PM.CollectParams({
          tokenId: params.oldTokenId,
          recipient: address(this),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
        })
      );

    uint256 collected0 = IERC20(token0).balanceOf(address(this)) - balance0Before;
    uint256 collected1 = IERC20(token1).balanceOf(address(this)) - balance1Before;

    uint256 feeAmount0 = collected0 * params.fees[0] / 1e6;
    uint256 feeAmount1 = collected1 * params.fees[1] / 1e6;

    if (feeAmount0 > 0) token0.safeTransfer(params.router, feeAmount0);
    if (feeAmount1 > 0) token1.safeTransfer(params.router, feeAmount1);

    token0.forceApprove(address(params.pm), params.amountDesireds[0]);
    token1.forceApprove(address(params.pm), params.amountDesireds[1]);

    params.pm
      .mint(
        IUniswapV3PM.MintParams({
          token0: token0,
          token1: token1,
          fee: fee,
          tickLower: params.newTickLower,
          tickUpper: params.newTickUpper,
          amount0Desired: params.amountDesireds[0],
          amount1Desired: params.amountDesireds[1],
          amount0Min: 0,
          amount1Min: 0,
          recipient: params.mainAddress,
          deadline: block.timestamp + 1 days
        })
      );
  }

  struct ZapMigrateUniswapV4Params {
    IPositionManager pm;
    uint256 oldTokenId;
    int24 newTickLower;
    int24 newTickUpper;
    address router;
    address mainAddress;
    uint256[] amountDesireds;
    uint256[] fees;
  }

  function _univ4PoolId(PoolKey memory key) private pure returns (bytes32 id) {
    assembly ('memory-safe') {
      id := keccak256(key, 0xa0)
    }
  }

  function _pancakev4PoolId(PancakePoolKey memory key) private pure returns (PoolId id) {
    assembly ('memory-safe') {
      id := keccak256(key, 0xc0)
    }
  }

  function _minU256(uint256 a, uint256 b) private pure returns (uint256) {
    return a < b ? a : b;
  }

  /// @dev Same fee rule as `zapMigrateUniswapV3`: fee_i = collected_i * fees[i] / 1e6, sent to `router`.
  function zapMigrateUniswapV4(ZapMigrateUniswapV4Params memory params) external payable {
    IPositionManager pm = params.pm;
    (PoolKey memory poolKey,) = pm.getPoolAndPositionInfo(params.oldTokenId);
    uint128 posLiq = pm.getPositionLiquidity(params.oldTokenId);

    bytes32 poolId = _univ4PoolId(poolKey);
    (uint160 sqrtP,,,) = pm.poolManager().getSlot0(poolId);

    uint256 balance0Before = poolKey.currency0.selfBalance();
    uint256 balance1Before = poolKey.currency1.selfBalance();

    bytes memory takeActions = new bytes(2);
    bytes[] memory takeParams = new bytes[](2);
    takeActions[0] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
    takeParams[0] = abi.encode(params.oldTokenId, posLiq, uint128(0), uint128(0), bytes(''));
    takeActions[1] = bytes1(uint8(Actions.TAKE_PAIR));
    takeParams[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
    pm.modifyLiquidities(abi.encode(takeActions, takeParams), type(uint256).max);

    uint256 collected0 = poolKey.currency0.selfBalance() - balance0Before;
    uint256 collected1 = poolKey.currency1.selfBalance() - balance1Before;

    uint256 fee0 = collected0 * params.fees[0] / 1e6;
    uint256 fee1 = collected1 * params.fees[1] / 1e6;
    poolKey.currency0.safeTransfer(params.router, fee0);
    poolKey.currency1.safeTransfer(params.router, fee1);

    uint128 newLiq = LiquidityAmounts.getLiquidityForAmounts(
      sqrtP,
      TickMath.getSqrtRatioAtTick(params.newTickLower),
      TickMath.getSqrtRatioAtTick(params.newTickUpper),
      params.amountDesireds[0],
      params.amountDesireds[1]
    );

    if (!poolKey.currency0.isNative()) {
      poolKey.currency0.forceApprove(PERMIT2, type(uint256).max);
      IAllowanceTransfer(PERMIT2)
        .approve(poolKey.currency0, address(pm), type(uint160).max, type(uint48).max);
    }
    if (!poolKey.currency1.isNative()) {
      poolKey.currency1.forceApprove(PERMIT2, type(uint256).max);
      IAllowanceTransfer(PERMIT2)
        .approve(poolKey.currency1, address(pm), type(uint160).max, type(uint48).max);
    }

    bytes memory mintActions = new bytes(2);
    bytes[] memory mintParams = new bytes[](2);
    mintActions[0] = bytes1(uint8(Actions.MINT_POSITION));
    mintParams[0] = abi.encode(
      poolKey,
      params.newTickLower,
      params.newTickUpper,
      uint256(newLiq),
      params.amountDesireds[0],
      params.amountDesireds[1],
      params.mainAddress,
      bytes('')
    );
    mintActions[1] = bytes1(uint8(Actions.SETTLE_PAIR));
    mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);

    uint256 ethValue = poolKey.currency0.isNative() ? address(this).balance : 0;
    pm.modifyLiquidities{value: ethValue}(abi.encode(mintActions, mintParams), type(uint256).max);
  }

  struct ZapMigratePancakeV4Params {
    ICLPositionManager pm;
    uint256 oldTokenId;
    int24 newTickLower;
    int24 newTickUpper;
    address router;
    address mainAddress;
    uint256[] amountDesireds;
    uint256[] fees;
  }

  function zapMigratePancakeV4(ZapMigratePancakeV4Params memory params) external payable {
    ICLPositionManager pm = params.pm;
    (PancakePoolKey memory poolKey,,, uint128 posLiq,,,) = pm.positions(params.oldTokenId);

    PoolId poolId = _pancakev4PoolId(poolKey);
    (uint160 sqrtP,,,) = pm.clPoolManager().getSlot0(poolId);

    uint256 balance0Before = poolKey.currency0.selfBalance();
    uint256 balance1Before = poolKey.currency1.selfBalance();

    bytes memory takeActions = new bytes(2);
    bytes[] memory takeParams = new bytes[](2);
    takeActions[0] = bytes1(uint8(PancakeActions.CL_DECREASE_LIQUIDITY));
    takeParams[0] = abi.encode(params.oldTokenId, posLiq, uint128(0), uint128(0), bytes(''));
    takeActions[1] = bytes1(uint8(PancakeActions.TAKE_PAIR));
    takeParams[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(this));
    pm.modifyLiquidities(abi.encode(takeActions, takeParams), type(uint256).max);

    uint256 collected0 = poolKey.currency0.selfBalance() - balance0Before;
    uint256 collected1 = poolKey.currency1.selfBalance() - balance1Before;

    uint256 fee0 = collected0 * params.fees[0] / 1e6;
    uint256 fee1 = collected1 * params.fees[1] / 1e6;
    poolKey.currency0.safeTransfer(params.router, fee0);
    poolKey.currency1.safeTransfer(params.router, fee1);

    uint128 newLiq = LiquidityAmounts.getLiquidityForAmounts(
      sqrtP,
      TickMath.getSqrtRatioAtTick(params.newTickLower),
      TickMath.getSqrtRatioAtTick(params.newTickUpper),
      params.amountDesireds[0],
      params.amountDesireds[1]
    );

    if (poolKey.currency0 != TokenHelper.NATIVE_ADDRESS) {
      poolKey.currency0.safeApprove(PERMIT2_BSC, 0);
      poolKey.currency0.safeApprove(PERMIT2_BSC, type(uint256).max);
      IAllowanceTransfer(PERMIT2_BSC).approve(
        poolKey.currency0, address(pm), type(uint160).max, type(uint48).max
      );
    }
    if (poolKey.currency1 != TokenHelper.NATIVE_ADDRESS) {
      poolKey.currency1.safeApprove(PERMIT2_BSC, 0);
      poolKey.currency1.safeApprove(PERMIT2_BSC, type(uint256).max);
      IAllowanceTransfer(PERMIT2_BSC).approve(
        poolKey.currency1, address(pm), type(uint160).max, type(uint48).max
      );
    }

    bytes memory mintActions = new bytes(2);
    bytes[] memory mintParams = new bytes[](2);
    mintActions[0] = bytes1(uint8(PancakeActions.CL_MINT_POSITION));
    mintParams[0] = abi.encode(
      poolKey,
      params.newTickLower,
      params.newTickUpper,
      newLiq,
      params.amountDesireds[0],
      params.amountDesireds[1],
      params.mainAddress,
      bytes('')
    );
    mintActions[1] = bytes1(uint8(PancakeActions.SETTLE_PAIR));
    mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);

    uint256 ethValue = poolKey.currency0 == TokenHelper.NATIVE_ADDRESS ? address(this).balance : 0;
    pm.modifyLiquidities{value: ethValue}(abi.encode(mintActions, mintParams), type(uint256).max);
  }

  fallback() external payable {}

  receive() external payable {}
}
