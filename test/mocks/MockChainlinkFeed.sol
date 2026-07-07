// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from 'src/interfaces/oracle/external/AggregatorV3Interface.sol';

contract MockChainlinkFeed is AggregatorV3Interface {
  uint8 internal _decimals;
  int256 public answer;
  uint256 public updatedAt;

  constructor(uint8 decimals_, int256 answer_) {
    _decimals = decimals_;
    answer = answer_;
    updatedAt = block.timestamp;
  }

  function decimals() external view returns (uint8) {
    return _decimals;
  }

  function setAnswer(int256 answer_) external {
    answer = answer_;
    updatedAt = block.timestamp;
  }

  function setUpdatedAt(uint256 updatedAt_) external {
    updatedAt = updatedAt_;
  }

  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    return (1, answer, updatedAt, updatedAt, 1);
  }
}
