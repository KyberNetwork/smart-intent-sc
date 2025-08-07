// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IKSBoringForwarder} from '../interfaces/vendors/IKSBoringForwarder.sol';

import {Address} from '@openzeppelin/contracts/utils/Address.sol';

import {ManagementBase} from 'lib/ks-common-sc/src/base/ManagementBase.sol';
import {ManagementRescuable} from 'lib/ks-common-sc/src/base/ManagementRescuable.sol';

import {IERC1155Receiver} from 'openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import {IERC721Receiver} from 'openzeppelin-contracts/contracts/interfaces/IERC721Receiver.sol';

contract KSBoringForwarder is
  IKSBoringForwarder,
  IERC1155Receiver,
  IERC721Receiver,
  ManagementRescuable
{
  using Address for address;

  constructor(address initialDefaultAdmin) ManagementBase(0, initialDefaultAdmin) {}

  function forwardPayable(address to, bytes calldata data) external payable returns (bytes memory) {
    return to.functionCallWithValue(data, msg.value);
  }

  function forward(address to, bytes calldata data, uint256 value) external returns (bytes memory) {
    return to.functionCallWithValue(data, value);
  }

  receive() external payable {}

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IERC721Receiver.onERC721Received.selector;
  }

  function onERC1155Received(address, address, uint256, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IERC1155Receiver.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external pure returns (bytes4) {
    return IERC1155Receiver.onERC1155BatchReceived.selector;
  }
}
