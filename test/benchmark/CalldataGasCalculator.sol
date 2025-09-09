// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title CalldataGasCalculator
 * @notice Library for calculating calldata gas costs
 * @dev Gas costs are based on EIP-2028:
 *      - Zero bytes: 4 gas
 *      - Non-zero bytes: 16 gas
 */
library CalldataGasCalculator {
  // Gas cost constants
  uint256 constant ZERO_BYTE_GAS = 4;
  uint256 constant NON_ZERO_BYTE_GAS = 16;

  /**
   * @notice Calculate the gas cost of calldata
   * @param data The calldata to analyze
   * @return totalGas The total gas cost for the calldata
   * @return zeroBytesCount Number of zero bytes
   * @return nonZeroBytesCount Number of non-zero bytes
   */
  function calculateCalldataGas(bytes calldata data)
    internal
    pure
    returns (uint256 totalGas, uint256 zeroBytesCount, uint256 nonZeroBytesCount)
  {
    uint256 length = data.length;

    for (uint256 i = 0; i < length; i++) {
      if (data[i] == 0) {
        zeroBytesCount++;
      } else {
        nonZeroBytesCount++;
      }
    }

    totalGas = (zeroBytesCount * ZERO_BYTE_GAS) + (nonZeroBytesCount * NON_ZERO_BYTE_GAS);
  }
}
