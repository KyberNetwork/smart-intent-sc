// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Base} from './Base.t.sol';

import {IPoolManager} from 'src/interfaces/uniswapv4/IPoolManager.sol';
import {IPositionManager} from 'src/interfaces/uniswapv4/IPositionManager.sol';
import {Actions, PoolKey} from 'src/interfaces/uniswapv4/Types.sol';
import {StateLibrary} from 'src/libraries/uniswapv4/StateLibrary.sol';
import {TickMath} from 'src/libraries/uniswapv4/TickMath.sol';

import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

interface IPoolManagerInitialize {
  function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
}

interface IPositionManagerExtra {
  function nextTokenId() external view returns (uint256);
}

interface IPermit2 {
  function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IPositionManagerPermit2 {
  function permit2() external view returns (address);
}

/**
 * @notice Removes liquidity through the deployed `KSRemoveLiquidityUniswapV4Hook`.
 */
contract CheckRemoveLiquidityUniswapV4 is Base {
  using StateLibrary for IPoolManager;

  uint24 constant POOL_FEE = 3000;
  int24 constant TICK_SPACING = 60;
  uint160 constant INITIAL_SQRT_PRICE = 79_228_162_514_264_337_593_543_950_336;
  uint128 constant MINT_LIQUIDITY = 1e18;

  IPoolManager poolManager;
  PoolKey poolKey;

  function _positionManagerNames() internal pure override returns (string[] memory names) {
    names = new string[](1);
    names[0] = 'UniswapV4PositionManager';
  }

  function _hookConfigKey() internal pure override returns (string memory) {
    return 'remove-liquidity-uniswap-v4-hook';
  }

  function _setUpPool() internal override {
    poolManager = IPositionManager(positionManager).poolManager();
    vm.label(address(poolManager), 'UniswapV4PoolManager');

    (token0, token1) = _deployPairedTokens();

    poolKey = PoolKey({
      currency0: token0,
      currency1: token1,
      fee: POOL_FEE,
      tickSpacing: TICK_SPACING,
      hooks: address(0)
    });
    IPoolManagerInitialize(address(poolManager)).initialize(poolKey, INITIAL_SQRT_PRICE);

    int24 currentTick = TickMath.getTickAtSqrtRatio(INITIAL_SQRT_PRICE);
    tickLower = ((currentTick / TICK_SPACING) - 10) * TICK_SPACING;
    tickUpper = ((currentTick / TICK_SPACING) + 10) * TICK_SPACING;
  }

  function _mintPosition() internal override returns (uint256 newTokenId, uint128 liquidity) {
    liquidity = MINT_LIQUIDITY;
    newTokenId = IPositionManagerExtra(positionManager).nextTokenId();

    _fundAndApprove(token0);
    _fundAndApprove(token1);

    bytes memory actions = new bytes(2);
    actions[0] = bytes1(uint8(Actions.MINT_POSITION));
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
    IPositionManager(positionManager)
      .modifyLiquidities(abi.encode(actions, params), block.timestamp + 1 days);
  }

  function _removeLiquidityCalls(uint256 liquidityToRemove)
    internal
    view
    override
    returns (bytes[] memory calls)
  {
    bytes memory actions = new bytes(2);
    actions[0] = bytes1(uint8(Actions.DECREASE_LIQUIDITY));
    actions[1] = bytes1(uint8(Actions.TAKE_PAIR));

    bytes[] memory params = new bytes[](2);
    params[0] = abi.encode(tokenId, liquidityToRemove, uint128(0), uint128(0), bytes(''));
    params[1] = abi.encode(poolKey.currency0, poolKey.currency1, address(router));

    calls = new bytes[](2);
    calls[0] = abi.encodeWithSelector(
      IPositionManager.modifyLiquidities.selector, abi.encode(actions, params), type(uint256).max
    );
    calls[1] =
      abi.encodeWithSelector(IERC721.transferFrom.selector, forwarder, mainAddress, tokenId);
  }

  function _currentSqrtPrice() internal view override returns (uint160 sqrtPriceX96) {
    (sqrtPriceX96,,,) = poolManager.getSlot0(StateLibrary.getPoolId(poolKey));
  }

  /// @dev Two freshly deployed tokens, already ordered the way a pool key requires.
  function _deployPairedTokens() internal returns (address lower, address upper) {
    address a = address(new ERC20Mock());
    address b = address(new ERC20Mock());
    (lower, upper) = a < b ? (a, b) : (b, a);

    vm.label(lower, 'LiveFlowToken0');
    vm.label(upper, 'LiveFlowToken1');
  }

  /// @dev Settlement pulls tokens through Permit2, so the main address approves the token to
  /// Permit2 and then Permit2 to the position manager. Which Permit2 that is comes from the
  /// position manager itself - Pancake, for one, runs its own fork at a different address.
  function _fundAndApprove(address token) internal {
    ERC20Mock(token).mint(mainAddress, 1e24);

    address permit2 = IPositionManagerPermit2(positionManager).permit2();

    vm.startPrank(mainAddress);
    IERC20(token).approve(permit2, type(uint256).max);
    IPermit2(permit2).approve(token, positionManager, type(uint160).max, type(uint48).max);
    vm.stopPrank();
  }
}
