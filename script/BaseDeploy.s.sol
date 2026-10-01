// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc-script/script/Base.s.sol';

/// @notice Deploys contracts by name via CREATE3 on one or more chains, reading their config from a
/// JSON file.
/// @dev Children supply the salt, config folder and config file, and override `_getConstructorArgs`
/// if any of their contracts take constructor arguments. Each chain's RPC URL comes from the
/// `RPC_<chainId>` env var (or a foundry.toml `rpc_endpoints` alias).
abstract contract BaseDeployScript is BaseScript {
  /// @param constructorParams The sources the child script resolves into constructor arguments
  /// @param exported The address file name, relative to the config file's folder
  struct DeployConfig {
    string[] constructorParams;
    string exported;
  }

  string salt;
  /// @dev Folder under script/config/ holding the config file and deployed addresses, e.g. 'hooks/'
  string configDir;
  string configFile;

  constructor(string memory _salt, string memory _configDir, string memory _configFile) {
    if (bytes(_salt).length == 0) {
      revert('salt is required');
    }
    salt = _salt;
    configDir = _configDir;
    configFile = _configFile;
  }

  /**
   * @notice Deploys `contractNames` on every chain in `chainIds`
   * @dev Usage:
   *   forge script script/DeployHooks.s.sol --sig "run(string[],string[])" \
   *     "[56,8453]" "[KSConditionalSwapHook]" --account <deployer> --broadcast
   *   A contract already deployed at its CREATE3 address is skipped and its address re-recorded.
   */
  function run(string[] memory chainIds, string[] memory contractNames)
    external
    multiChain(chainIds)
  {
    // Read deploy configurations from JSON
    string memory json = vm.readFile(string.concat(path, configDir, configFile));

    for (uint256 i = 0; i < contractNames.length; i++) {
      string memory contractName = contractNames[i];

      // Parse the config for this specific contract
      DeployConfig memory config =
        abi.decode(vm.parseJson(json, string.concat('.', contractName)), (DeployConfig));

      (address deployed, bool success) = _deployContract(contractName, config);

      _writeAddress(string.concat(configDir, config.exported), deployed);
      if (success) {
        console.log('Deployed %s at %s on chain %s', contractName, deployed, block.chainid);
      } else {
        console.log('Skipped %s, already at %s on chain %s', contractName, deployed, block.chainid);
      }
    }
  }

  function _deployContract(string memory contractName, DeployConfig memory config)
    internal
    returns (address deployed, bool success)
  {
    bytes memory creationCode = abi.encodePacked(
      vm.getCode(contractName), _getConstructorArgs(config.constructorParams)
    );
    string memory contractSalt = string.concat(contractName, '_', salt);

    return _createXDeploy(keccak256(abi.encodePacked(contractSalt)), creationCode);
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
