// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface IPyth {
  struct Price {
    int64 price;
    uint64 conf;
    int32 expo;
    uint256 publishTime;
  }

  function getUpdateFee(bytes[] calldata updateData) external view returns (uint256 feeAmount);

  function updatePriceFeeds(bytes[] calldata updateData) external payable;

  function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory price);
}
