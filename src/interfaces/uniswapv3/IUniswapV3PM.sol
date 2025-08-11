// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

interface IUniswapV3PM is IERC721 {
  function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

  /// @notice Unwraps the contract's WETH9 balance and sends it to recipient as ETH.
  /// @dev The amountMinimum parameter prevents malicious contracts from stealing WETH9 from users.
  /// @param amountMinimum The minimum amount of WETH9 to unwrap
  /// @param recipient The address receiving ETH
  function unwrapWETH9(uint256 amountMinimum, address recipient) external payable;

  /// @notice Transfers the full amount of a token held by this contract to recipient
  /// @dev The amountMinimum parameter prevents malicious contracts from stealing the token from users
  /// @param token The contract address of the token which will be transferred to `recipient`
  /// @param amountMinimum The minimum amount of token required for a transfer
  /// @param recipient The destination address of the token
  function sweepToken(address token, uint256 amountMinimum, address recipient) external payable;

  struct DecreaseLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
  }

  /// @notice Decreases the amount of liquidity in a position and accounts it to the position
  /// @param params tokenId The ID of the token for which liquidity is being decreased,
  /// amount The amount by which liquidity will be decreased,
  /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
  /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
  /// deadline The time by which the transaction must be included to effect the change
  /// @return amount0 The amount of token0 accounted to the position's tokens owed
  /// @return amount1 The amount of token1 accounted to the position's tokens owed
  function decreaseLiquidity(DecreaseLiquidityParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1);

  function positions(uint256 tokenId)
    external
    view
    returns (
      uint96 nonce,
      address operator,
      address token0,
      address token1,
      uint24 fee,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      uint256 feeGrowthInside0LastX128,
      uint256 feeGrowthInside1LastX128,
      uint128 tokensOwed0,
      uint128 tokensOwed1
    );

  struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
  /// @param params tokenId The ID of the NFT for which tokens are being collected,
  /// recipient The account that should receive the tokens,
  /// amount0Max The maximum amount of token0 to collect,
  /// amount1Max The maximum amount of token1 to collect
  /// @return amount0 The amount of fees collected in token0
  /// @return amount1 The amount of fees collected in token1
  function collect(CollectParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1);

  function factory() external view returns (address);
}
