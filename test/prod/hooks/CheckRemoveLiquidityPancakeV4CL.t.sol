// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Base} from './Base.t.sol';

import {ICLPoolManager} from 'src/interfaces/pancakev4/ICLPoolManager.sol';
import {ICLPositionManager} from 'src/interfaces/pancakev4/ICLPositionManager.sol';
import {Actions, PoolId, PoolKey} from 'src/interfaces/pancakev4/Types.sol';
import {TickMath} from 'src/libraries/uniswapv4/TickMath.sol';

import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

interface IPermit2 {
  function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IPositionManagerPermit2 {
  function permit2() external view returns (address);
}

/**
 * @notice Removes liquidity through the deployed `KSRemoveLiquidityPancakeV4CLHook`
 */
contract CheckRemoveLiquidityPancakeV4CL is Base {
  uint24 constant POOL_FEE = 3000;
  int24 constant TICK_SPACING = 60;
  uint256 constant TICK_SPACING_OFFSET = 16;
  uint160 constant INITIAL_SQRT_PRICE = 79_228_162_514_264_337_593_543_950_336;
  uint128 constant MINT_LIQUIDITY = 1e18;

  ICLPoolManager clPoolManager;
  PoolKey poolKey;

  function _positionManagerNames() internal pure override returns (string[] memory names) {
    names = new string[](1);
    names[0] = 'PancakeInfinityCLPositionManager';
  }

  function _hookConfigKey() internal pure override returns (string memory) {
    return 'remove-liquidity-pancake-v4cl-hook';
  }

  function _setUpPool() internal override {
    clPoolManager = ICLPositionManager(positionManager).clPoolManager();
    vm.label(address(clPoolManager), 'PancakeCLPoolManager');

    (token0, token1) = _deployPairedTokens();

    poolKey = PoolKey({
      currency0: token0,
      currency1: token1,
      hooks: address(0),
      poolManager: address(clPoolManager),
      fee: POOL_FEE,
      parameters: bytes32(uint256(uint24(TICK_SPACING)) << TICK_SPACING_OFFSET)
    });
    ICLPositionManager(positionManager).initializePool(poolKey, INITIAL_SQRT_PRICE);

    int24 currentTick = TickMath.getTickAtSqrtRatio(INITIAL_SQRT_PRICE);
    tickLower = ((currentTick / TICK_SPACING) - 10) * TICK_SPACING;
    tickUpper = ((currentTick / TICK_SPACING) + 10) * TICK_SPACING;
  }

  function _mintPosition() internal override returns (uint256 newTokenId, uint128 liquidity) {
    liquidity = MINT_LIQUIDITY;
    newTokenId = ICLPositionManager(positionManager).nextTokenId();

    _fundAndApprove(token0);
    _fundAndApprove(token1);

    bytes memory actions = new bytes(2);
    actions[0] = bytes1(uint8(Actions.CL_MINT_POSITION));
    actions[1] = bytes1(uint8(Actions.SETTLE_PAIR));

    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(
      poolKey,
      tickLower,
      tickUpper,
      uint256(liquidity),
      type(uint128).max,
      type(uint128).max,
      mainAddress,
      bytes('')
    );
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

    vm.prank(mainAddress);
    ICLPositionManager(positionManager)
      .modifyLiquidities(abi.encode(actions, params), block.timestamp + 1 days);
  }

  function _removeLiquidityCalls(uint256 liquidityToRemove)
    internal
    view
    override
    returns (bytes[] memory calls)
  {
    bytes memory actions = new bytes(2);
    actions[0] = bytes1(uint8(Actions.CL_DECREASE_LIQUIDITY));
    actions[1] = bytes1(uint8(Actions.TAKE_PAIR));

    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(tokenId, liquidityToRemove, uint128(0), uint128(0), bytes(''));
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(router));

    calls = new bytes[](2);
    calls[0] = abi.encodeWithSelector(
      ICLPositionManager.modifyLiquidities.selector, abi.encode(actions, params), type(uint256).max
    );
    calls[1] =
      abi.encodeWithSelector(IERC721.transferFrom.selector, forwarder, mainAddress, tokenId);
  }

  function _currentSqrtPrice() internal view override returns (uint160 sqrtPriceX96) {
    (sqrtPriceX96,,,) = clPoolManager.getSlot0(_toId(poolKey));
  }

  function _toId(PoolKey memory key) internal pure returns (PoolId poolId) {
    assembly ('memory-safe') {
      poolId := keccak256(key, 0xc0)
    }
  }

  function _deployPairedTokens() internal returns (address lower, address upper) {
    address a = address(new ERC20Mock());
    address b = address(new ERC20Mock());
    (lower, upper) = a < b ? (a, b) : (b, a);

    vm.label(lower, 'LiveFlowToken0');
    vm.label(upper, 'LiveFlowToken1');
  }

  function _fundAndApprove(address token) internal {
    ERC20Mock(token).mint(mainAddress, 1e24);

    address permit2 = IPositionManagerPermit2(positionManager).permit2();

    vm.startPrank(mainAddress);
    IERC20(token).approve(permit2, type(uint256).max);
    IPermit2(permit2).approve(token, positionManager, type(uint160).max, type(uint48).max);
    vm.stopPrank();
  }
}
