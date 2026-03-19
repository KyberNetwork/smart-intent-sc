// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/// @notice Fuzz input for zap-migrate mint amounts and hook/action fee fields (1e6 = 100%).
struct ZapMigrateFuzzParams {
  uint256 amountDesired0;
  uint256 amountDesired1;
  uint256 maxFee0;
  uint256 maxFee1;
  uint256 fee0Percent;
  uint256 fee1Percent;
}
