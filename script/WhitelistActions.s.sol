// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity ^0.8.0;

// import './Base.s.sol';

// import {KSSmartIntentRouter} from 'src/KSSmartIntentRouter.sol';
// import {IKSSmartIntentRouter} from 'src/interfaces/routers/IKSSmartIntentRouter.sol';

// contract WhitelistActions is BaseScript {
//   address[] unWhitelistedContracts;
//   bytes4[] unWhitelistedSelectors;

//   function run() external {
//     string memory root = vm.projectRoot();
//     uint256 chainId;
//     assembly ("memory-safe") {
//       chainId := chainid()
//     }
//     console.log('chainId is %s', chainId);

//     address router =
//       _readAddress(string(abi.encodePacked(root, '/script/deployedAddresses/router.json')), chainId);
//     console.log('router is %s', router);

//     (address[] memory actionContracts, bytes4[] memory actionSelectors) = _readSwapRouterAddresses(
//       string(abi.encodePacked(root, '/script/config/whitelisted-actions.json')), chainId
//     );

//     require(
//       actionContracts.length == actionSelectors.length,
//       'actionContracts and actionSelectors length mismatch'
//     );

//     for (uint256 i; i < actionContracts.length; ++i) {
//       if (!KSSmartIntentRouter(router).whitelistedActions(actionContracts[i], actionSelectors[i])) {
//         unWhitelistedContracts.push(actionContracts[i]);
//         unWhitelistedSelectors.push(actionSelectors[i]);
//       }
//     }

//     vm.startBroadcast();
//     IKSSmartIntentRouter(router).whitelistActions(
//       unWhitelistedContracts, unWhitelistedSelectors, true
//     );
//     vm.stopBroadcast();
//   }
// }
