// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IKSBoringForwarder {
  function forwardPayable(address to, bytes calldata data) external payable returns (bytes memory);

  function forward(address to, bytes calldata data, uint256 value) external returns (bytes memory);
}
