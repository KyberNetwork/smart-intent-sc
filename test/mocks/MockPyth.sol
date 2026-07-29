// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IPyth} from 'src/interfaces/oracle/external/IPyth.sol';

contract MockPyth is IPyth {
  error InsufficientFee();
  error StalePrice();
  error NoPrice();

  uint256 public fee;
  uint256 public updateCount;
  mapping(bytes32 => Price) internal _prices;

  constructor(uint256 fee_) {
    fee = fee_;
  }

  function setPrice(bytes32 id, int64 price, int32 expo, uint256 publishTime) external {
    _prices[id] = Price({price: price, conf: 0, expo: expo, publishTime: publishTime});
  }

  function getUpdateFee(bytes[] calldata) external view returns (uint256) {
    return fee;
  }

  function updatePriceFeeds(bytes[] calldata updateData) external payable {
    if (msg.value < fee) revert InsufficientFee();
    updateCount++;
    for (uint256 i; i < updateData.length; ++i) {
      (bytes32 id, int64 price, int32 expo, uint256 publishTime) =
        abi.decode(updateData[i], (bytes32, int64, int32, uint256));
      _prices[id] = Price({price: price, conf: 0, expo: expo, publishTime: publishTime});
    }
  }

  function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory) {
    Price memory price = _prices[id];
    if (price.publishTime == 0) revert NoPrice();
    if (block.timestamp - price.publishTime > age) revert StalePrice();
    return price;
  }
}
