// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity ^0.8.0;

// import 'src/validators/base/BaseIntentValidator.sol';

// contract MockIntentValidator is BaseIntentValidator {
//   modifier checkTokenLengths(IKSSmartIntentRouter.TokenData calldata tokenData) override {
//     _;
//   }

//   function validateBeforeExecution(
//     bytes32,
//     IKSSmartIntentRouter.IntentCoreData calldata coreData,
//     IKSSmartIntentRouter.ActionData calldata actionData
//   ) external view returns (bytes memory beforeExecutionData) {}

//   function validateAfterExecution(
//     bytes32,
//     IKSSmartIntentRouter.IntentCoreData calldata coreData,
//     bytes calldata beforeExecutionData,
//     bytes calldata actionResult
//   ) external view {}
// }
