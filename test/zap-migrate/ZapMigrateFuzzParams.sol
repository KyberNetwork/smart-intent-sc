// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

struct ZapMigrateUniswapV3FuzzParams {
  uint8 mintRangeMultiplier;
  uint8 newRangeMultiplier;
  uint256 mintAmount0Desired;
  uint256 mintAmount1Desired;
  uint256 actionAmount0Desired;
  uint256 actionAmount1Desired;
  uint24 actionFee0;
  uint24 actionFee1;
  uint256 maxFee0;
  uint256 maxFee1;
  int24 maxDistanceFromLowerTickBeforeMigration;
  int24 maxDistanceFromUpperTickBeforeMigration;
  int24 minDistanceFromLowerTickAfterMigration;
  int24 minDistanceFromUpperTickAfterMigration;
  int24 minTickRangeLength;
  int24 maxTickRangeLength;
  uint256 minValueInToken0;
  uint256 minValueInToken1;
  uint256 maxValueReductionPerAction;
  uint256 invalidTokenErc20Amount;
  uint256 samplePositionIndex;
}
