// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

contract BaseScript is Script {
  using stdJson for string;

  struct SwapRouterInfo {
    address router;
    bytes selector;
  }

  struct ValidatorInfo {
    address validator;
    string name;
  }

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

  function _readString(string memory path, string memory key) internal view returns (string memory) {
    string memory json = vm.readFile(path);
    return json.readString(string.concat('.', key));
  }

  function _readSwapRouterAddresses(string memory path, uint256 chainId)
    internal
    view
    returns (address[] memory addresses, bytes4[] memory selectors)
  {
    string memory json = vm.readFile(path);
    bytes memory data = json.parseRaw(string.concat('.', vm.toString(chainId)));
    SwapRouterInfo[] memory swapRouterInfos = abi.decode(data, (SwapRouterInfo[]));

    addresses = new address[](swapRouterInfos.length);
    selectors = new bytes4[](swapRouterInfos.length);
    for (uint256 i; i < swapRouterInfos.length; i++) {
      addresses[i] = swapRouterInfos[i].router;
      selectors[i] = bytes4(swapRouterInfos[i].selector);
    }
  }

  function _readValidatorAddresses(string memory path, uint256 chainId)
    internal
    view
    returns (string[] memory validators, address[] memory addresses)
  {
    string memory json = vm.readFile(path);
    bytes memory data = json.parseRaw(string.concat('.', vm.toString(chainId)));
    ValidatorInfo[] memory validatorInfos = abi.decode(data, (ValidatorInfo[]));

    validators = new string[](validatorInfos.length);
    addresses = new address[](validatorInfos.length);
    for (uint256 i; i < validatorInfos.length; i++) {
      validators[i] = validatorInfos[i].name;
      addresses[i] = validatorInfos[i].validator;
    }
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

  function _writeAddress(string memory path, string memory file, uint256 chainId, address value)
    internal
  {
    if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
      return;
    }
    vm.serializeJson(file, _getJsonString(path, file));
    vm.writeJson(file.serialize(vm.toString(chainId), value), string.concat(path, file, '.json'));
  }

  function _writeAddress(
    string memory path,
    string memory file,
    uint256 chainId,
    string[] memory keys,
    address[] memory values
  ) internal {
    if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
      return;
    }

    vm.serializeJson(file, _getJsonString(path, file));
    string[] memory rows = new string[](keys.length);
    for (uint256 i; i < keys.length; i++) {
      string memory row;
      string memory name;
      string memory addr;
      rows[i] = rows[i].serialize(row.serialize(addr.serialize('address', values[i])));
      rows[i] = rows[i].serialize(row.serialize(name.serialize('name', keys[i])));
    }

    vm.writeJson(file.serialize(vm.toString(chainId), rows), string.concat(path, file, '.json'));
  }

  function _toArray(address a) internal pure returns (address[] memory) {
    address[] memory array = new address[](1);
    array[0] = a;
    return array;
  }

  function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
    return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
  }
}
