// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './BaseDeploy.s.sol';

contract DeployOracleAdapters is BaseDeployScript {
  constructor() BaseDeployScript('260929', 'oracle-adapters/', 'oracle-adapter-configs.json') {}

  function _getConstructorArgs(string[] memory paramSources)
    internal
    override
    returns (bytes memory)
  {
    // Chainlink and Pyth adapters are stateless and take no arguments
    if (paramSources.length == 0) {
      return '';
    }

    // AtlasOracleAdapter(address initialAdmin, address[] initialSigners): the static and dynamic
    // arguments must be encoded together, so the pair is resolved as a unit
    if (
      paramSources.length == 2 && keccak256(bytes(paramSources[0])) == keccak256('admin')
        && keccak256(bytes(paramSources[1])) == keccak256('atlas-signers')
    ) {
      return abi.encode(
        _readAddress('router-admin'),
        _readAddressArray(string.concat(configDir, 'atlas-oracle-signers'))
      );
    }

    revert('Unsupported constructor parameter sources');
  }
}
