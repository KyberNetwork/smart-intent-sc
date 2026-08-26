// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Base} from './Base.t.sol';

import {IUniswapV3PM} from 'src/interfaces/uniswapv3/IUniswapV3PM.sol';
import {IUniswapV3Pool} from 'src/interfaces/uniswapv3/IUniswapV3Pool.sol';

import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

interface IUniswapV3Factory {
  function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

interface IUniswapV3PMMint {
  function createAndInitializePoolIfNecessary(
    address token0,
    address token1,
    uint24 fee,
    uint160 sqrtPriceX96
  ) external payable returns (address pool);

  struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
  }

  function mint(MintParams calldata params)
    external
    payable
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IUniswapV3PoolImmutables {
  function token0() external view returns (address);
  function token1() external view returns (address);
  function fee() external view returns (uint24);
  function tickSpacing() external view returns (int24);
}

/**
 * @notice Removes liquidity through the deployed `KSRemoveLiquidityUniswapV3Hook`.
 */
contract CheckRemoveLiquidityUniswapV3 is Base {
  uint24[4] CANDIDATE_FEES = [uint24(3000), 2500, 500, 10_000];

  uint24 poolFee;
  int24 tickSpacing;

  uint160 constant INITIAL_SQRT_PRICE = 79_228_162_514_264_337_593_543_950_336;
  uint256 constant MINT_AMOUNT = 1e21;

  IUniswapV3Pool pool;

  function _positionManagerNames() internal pure override returns (string[] memory names) {
    names = new string[](3);
    names[0] = 'UniswapV3PositionManager';
    names[1] = 'PancakeV3PositionManager';
    names[2] = 'SushiSwapV3PositionManager';
  }

  function _hookConfigKey() internal pure override returns (string memory) {
    return 'remove-liquidity-uniswap-v3-hook';
  }

  function _setUpPool() internal override {
    (poolFee, tickSpacing) = _enabledFeeTier();
    (token0, token1) = _deployPairedTokens();

    pool = IUniswapV3Pool(
      IUniswapV3PMMint(positionManager)
        .createAndInitializePoolIfNecessary(token0, token1, poolFee, INITIAL_SQRT_PRICE)
    );
    assertGt(address(pool).code.length, 0, 'the pool was not created');
    vm.label(address(pool), 'UniswapV3Pool');

    (, int24 currentTick,,,,,) = pool.slot0();
    tickLower = ((currentTick / tickSpacing) - 10) * tickSpacing;
    tickUpper = ((currentTick / tickSpacing) + 10) * tickSpacing;
  }

  /// @dev The first candidate tier this position manager's factory enables, with its tick spacing.
  function _enabledFeeTier() internal view returns (uint24 fee, int24 spacing) {
    IUniswapV3Factory factory = IUniswapV3Factory(IUniswapV3PM(positionManager).factory());

    for (uint256 i = 0; i < CANDIDATE_FEES.length; i++) {
      spacing = factory.feeAmountTickSpacing(CANDIDATE_FEES[i]);
      if (spacing != 0) return (CANDIDATE_FEES[i], spacing);
    }

    revert('the factory enables none of the candidate fee tiers');
  }

  /// @dev Two freshly deployed tokens, already in the order a pool requires.
  function _deployPairedTokens() internal returns (address lower, address upper) {
    address a = address(new ERC20Mock());
    address b = address(new ERC20Mock());
    (lower, upper) = a < b ? (a, b) : (b, a);

    vm.label(lower, 'CheckToken0');
    vm.label(upper, 'CheckToken1');
  }

  function _mintPosition() internal override returns (uint256 newTokenId, uint128 liquidity) {
    ERC20Mock(token0).mint(mainAddress, MINT_AMOUNT);
    ERC20Mock(token1).mint(mainAddress, MINT_AMOUNT);

    vm.startPrank(mainAddress);
    IERC20(token0).approve(positionManager, MINT_AMOUNT);
    IERC20(token1).approve(positionManager, MINT_AMOUNT);

    (newTokenId, liquidity,,) = IUniswapV3PMMint(positionManager)
      .mint(
        IUniswapV3PMMint.MintParams({
        token0: token0,
        token1: token1,
        fee: poolFee,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: MINT_AMOUNT,
        amount1Desired: MINT_AMOUNT,
        amount0Min: 0,
        amount1Min: 0,
        recipient: mainAddress,
        deadline: block.timestamp + 1 days
      })
      );
    vm.stopPrank();
  }

  /// @dev The position manager runs through the forwarder, so the NFT is returned from there and
  /// the tokens are swept to the router for the hook to distribute.
  function _removeLiquidityCalls(uint256 liquidityToRemove)
    internal
    view
    override
    returns (bytes[] memory calls)
  {
    calls = new bytes[](5);
    calls[0] = abi.encodeWithSelector(
      IUniswapV3PM.decreaseLiquidity.selector,
      IUniswapV3PM.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: uint128(liquidityToRemove),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1 days
      })
    );
    calls[1] = abi.encodeWithSelector(
      IUniswapV3PM.collect.selector,
      IUniswapV3PM.CollectParams({
        tokenId: tokenId,
        recipient: positionManager,
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
    calls[2] =
      abi.encodeWithSelector(IERC721.transferFrom.selector, forwarder, mainAddress, tokenId);
    calls[3] = abi.encodeWithSelector(IUniswapV3PM.sweepToken.selector, token0, 0, address(router));
    calls[4] = abi.encodeWithSelector(IUniswapV3PM.sweepToken.selector, token1, 0, address(router));
  }

  function _currentSqrtPrice() internal view override returns (uint160 sqrtPriceX96) {
    (sqrtPriceX96,,,,,,) = pool.slot0();
  }

  function _hookAdditionalData() internal view override returns (bytes memory) {
    address[] memory pools = new address[](1);
    pools[0] = address(pool);
    return abi.encode(pools);
  }
}
