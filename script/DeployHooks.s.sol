// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './BaseDeploy.s.sol';

contract DeployHooks is BaseDeployScript {
  constructor() BaseDeployScript('260205', 'hook-configs.json') {}

  function _getConstructorArgs(string[] memory paramSources)
    internal
    override
    returns (bytes memory)
  {
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
