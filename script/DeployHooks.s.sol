// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';

contract DeployHooks is BaseScript {
  string salt = '251020';

  struct HookConfig {
    string[] constructorParams;
    string exported;
  }

  function run(string[] memory hookNames) external {
    if (bytes(salt).length == 0) {
      revert('salt is required');
    }
    // Read hook configurations from JSON
    string memory json = vm.readFile('./script/config/hook-configs.json');

    vm.startBroadcast();

    for (uint256 i = 0; i < hookNames.length; i++) {
      string memory hookName = hookNames[i];

      // Parse the hook config for this specific hook
      HookConfig memory config =
        abi.decode(vm.parseJson(json, string.concat('.', hookName)), (HookConfig));

      address deployedHook = _deployHook(hookName, config);

      _writeAddress(config.exported, deployedHook);
      console.log('Deployed %s at %s', hookName, deployedHook);
    }

    vm.stopBroadcast();
  }

  function _deployHook(string memory hookName, HookConfig memory config) internal returns (address) {
    bytes memory constructorArgs = _getConstructorArgs(config.constructorParams);
    string memory hookSalt = string.concat(hookName, '_', salt);

    return _deployContract(hookName, constructorArgs, hookSalt);
  }

  function _deployContract(
    string memory contractName,
    bytes memory constructorArgs,
    string memory hookSalt
  ) internal returns (address) {
    bytes memory bytecode = vm.getCode(contractName);
    bytes memory creationCode = abi.encodePacked(bytecode, constructorArgs);
    return _create3Deploy(keccak256(abi.encodePacked(hookSalt)), creationCode);
  }

  function _getConstructorArgs(string[] memory paramSources) internal returns (bytes memory) {
    if (paramSources.length == 0) {
      return '';
    }

    if (paramSources.length == 1) {
      string memory source = paramSources[0];

      if (keccak256(bytes(source)) == keccak256('weth')) {
        return abi.encode(_readAddress('weth'));
      }

      if (keccak256(bytes(source)) == keccak256('routers')) {
        address[] memory routers = new address[](1);
        routers[0] = _readAddress('router');
        return abi.encode(routers);
      }

      revert(string.concat('Unsupported parameter source: ', source));
    }

    revert('Multiple constructor parameters not supported yet');
  }
}
