// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

contract BaseScript is Script {
  using stdJson for string;

  struct Swap {
    bytes data;
    bytes32 selectorAndFlags; // [selector (32 bits) + flags (224 bits)]; selector is 4 most significant bytes; flags are stored in 4 least significant bytes.
  }

  struct SwapExecutorDescription {
    Swap[][] swapSequences;
    address tokenIn;
    address tokenOut;
    address to;
    uint256 deadline;
    bytes positiveSlippageData;
  }

  function _readAddress(string memory path, uint256 chainId) internal view returns (address) {
    string memory json = vm.readFile(path);
    return json.readAddress(string.concat('.', vm.toString(chainId)));
  }

  function _readBool(string memory path, uint256 chainId) internal view returns (bool) {
    string memory json = vm.readFile(path);
    return json.readBool(string.concat('.', vm.toString(chainId)));
  }

  function _readAddressArray(string memory path, uint256 chainId)
    internal
    view
    returns (address[] memory)
  {
    string memory json = vm.readFile(path);
    return json.readAddressArray(string.concat('.', vm.toString(chainId)));
  }

  function _readBytes(string memory path, uint256 chainId) internal view returns (bytes memory) {
    string memory json = vm.readFile(path);
    return json.readBytes(string.concat('.', vm.toString(chainId)));
  }

  function _toArray(address a) internal pure returns (address[] memory) {
    address[] memory array = new address[](1);
    array[0] = a;
    return array;
  }
}
