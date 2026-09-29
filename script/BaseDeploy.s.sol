// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';

/// @notice Deploys contracts by name via CREATE3, reading their config from a JSON file.
/// @dev Children supply the salt and config file, and override `_getConstructorArgs`
/// if any of their contracts take constructor arguments.
abstract contract BaseDeployScript is BaseScript {
  struct DeployConfig {
    string[] constructorParams;
    string exported;
  }

  string salt;
  string configFile;

  constructor(string memory _salt, string memory _configFile) {
    if (bytes(_salt).length == 0) {
      revert('salt is required');
    }
    salt = _salt;
    configFile = _configFile;
  }

  function run(string[] memory contractNames) external {
    // Read deploy configurations from JSON
    string memory json = vm.readFile(string.concat(path, configFile));

    vm.startBroadcast();

    for (uint256 i = 0; i < contractNames.length; i++) {
      string memory contractName = contractNames[i];

      // Parse the config for this specific contract
      DeployConfig memory config =
        abi.decode(vm.parseJson(json, string.concat('.', contractName)), (DeployConfig));

      address deployed = _deployContract(contractName, config);

      _writeAddress(config.exported, deployed);
      console.log('Deployed %s at %s', contractName, deployed);
    }

    vm.stopBroadcast();
  }

  function _deployContract(string memory contractName, DeployConfig memory config)
    internal
    returns (address)
  {
    bytes memory creationCode = abi.encodePacked(
      vm.getCode(contractName), _getConstructorArgs(config.constructorParams)
    );
    string memory contractSalt = string.concat(contractName, '_', salt);

    return _create3Deploy(keccak256(abi.encodePacked(contractSalt)), creationCode);
  }

  /// @dev Resolves constructor arguments from their config sources. Defaults to no arguments.
  function _getConstructorArgs(string[] memory paramSources)
    internal
    virtual
    returns (bytes memory)
  {
    if (paramSources.length == 0) {
      return '';
    }

    revert(string.concat('Unsupported parameter source: ', paramSources[0]));
  }
}
