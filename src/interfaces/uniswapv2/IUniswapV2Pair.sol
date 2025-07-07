// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV2Pair {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function skim(address to) external;
}
