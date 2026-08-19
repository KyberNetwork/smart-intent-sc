// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './BaseDeploy.s.sol';

contract DeployOracleAdapters is BaseDeployScript {
  // Oracle adapters are stateless, so `_getConstructorArgs` is left at its no-args default
  constructor() BaseDeployScript('260819', 'oracle-adapter-configs.json') {}
}
