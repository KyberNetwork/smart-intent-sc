// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

contract BaseScript is Script {
  using stdJson for string;

  function _readAddress(string memory path, uint256 chainId) internal view returns (address) {
    string memory json = vm.readFile(path);
    return json.readAddress(string.concat('.', vm.toString(chainId)));
  }

  function _readAddress(string memory path, string memory key) internal view returns (address) {
    string memory json = vm.readFile(path);
    return json.readAddress(string.concat('.', key));
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

  function _readBytes(string memory path, string memory key) internal view returns (bytes memory) {
    string memory json = vm.readFile(path);
    return json.readBytes(string.concat('.', key));
  }

  function _readUint(string memory path, string memory key) internal view returns (uint256) {
    string memory json = vm.readFile(path);
    return json.readUint(string.concat('.', key));
  }

  function _getJsonString(string memory path, string memory key)
    internal
    view
    returns (string memory)
  {
    try vm.readFile(string.concat(path, key, '.json')) returns (string memory json) {
      return json;
    } catch {
      return '{}';
    }
  }

  function _writeAddress(string memory path, uint256 chainId, string memory key, address value)
    internal
  {
    if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
      return;
    }
    vm.serializeJson(key, _getJsonString(path, key));
    vm.writeJson(key.serialize(vm.toString(chainId), value), string.concat(path, key, '.json'));
  }

  function _toArray(address a) internal pure returns (address[] memory) {
    address[] memory array = new address[](1);
    array[0] = a;
    return array;
  }
}
