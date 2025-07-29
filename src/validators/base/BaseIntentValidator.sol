// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/interfaces/validators/IKSSessionIntentValidator.sol';

abstract contract BaseIntentValidator is IKSSessionIntentValidator {
  error InvalidTokenData();

  modifier checkTokenLengths(IKSSessionIntentRouter.TokenData calldata tokenData) virtual;
}
