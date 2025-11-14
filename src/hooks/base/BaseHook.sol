// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IKSSmartIntentHook} from '../../interfaces/hooks/IKSSmartIntentHook.sol';

import {ActionData} from '../../types/ActionData.sol';

abstract contract BaseHook is IKSSmartIntentHook {
  error InvalidTokenData();

  modifier checkTokenLengths(ActionData calldata actionData) virtual;
}
