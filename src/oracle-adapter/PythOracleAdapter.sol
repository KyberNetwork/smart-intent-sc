// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IOracleAdapter} from '../interfaces/oracle/IOracleAdapter.sol';
import {IPyth} from '../interfaces/oracle/external/IPyth.sol';
import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {OracleLib, TokenOracle} from 'src/types/OracleConfig.sol';

contract PythOracleAdapter is IOracleAdapter {
  using CalldataDecoder for bytes;

  error OracleConfidenceTooWide(uint256 conf, uint256 price, uint256 maxConfRatio);

  /**
   * @inheritdoc IOracleAdapter
   */
  function getPrice(TokenOracle calldata oracle) external view returns (uint256 price) {
    (uint256 maxStaleness, address source) = oracle.source.unpack();

    IPyth.Price memory pythPrice =
      IPyth(source).getPriceNoOlderThan(oracle.additionalData.decodeBytes32(), maxStaleness);
    if (pythPrice.price <= 0) revert InvalidOraclePrice();

    uint256 rawPrice = uint256(uint64(pythPrice.price));

    uint256 maxConfRatio = oracle.additionalData.decodeUint256(1);
    uint256 confRatio = Math.mulDiv(uint256(pythPrice.conf), OracleLib.PRECISION, rawPrice);
    if (confRatio > maxConfRatio) {
      revert OracleConfidenceTooWide(pythPrice.conf, rawPrice, maxConfRatio);
    }

    int256 exponent = int256(pythPrice.expo) + 18;
    if (exponent >= 0) {
      price = rawPrice * (10 ** uint256(exponent));
    } else {
      price = rawPrice / (10 ** uint256(-exponent));
    }
    if (price == 0) revert InvalidOraclePrice();
  }
}
