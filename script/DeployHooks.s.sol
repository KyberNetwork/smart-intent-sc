// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';

import 'src/hooks/swap/KSPriceBasedDCAHook.sol';
import 'src/hooks/swap/KSTimeBasedDCAHook.sol';

contract DeployHooks is BaseScript {
  string salt = '';

  function run() external {
    if (bytes(salt).length == 0) {
      revert('salt is required');
    }

    address router = _readAddress('router');

    vm.startBroadcast();

    address[] memory routers = new address[](1);
    routers[0] = router;

    // Deploy KSPriceBasedDCAHook using CREATE3
    string memory priceBasedSalt = string.concat('KSPriceBasedDCAHook_', salt);
    bytes memory priceBasedCreationCode =
      abi.encodePacked(type(KSPriceBasedDCAHook).creationCode, abi.encode(routers));
    address priceBasedDCAHook =
      _create3Deploy(keccak256(abi.encodePacked(priceBasedSalt)), priceBasedCreationCode);

    // Deploy KSTimeBasedDCAHook using CREATE3
    string memory timeBasedSalt = string.concat('KSTimeBasedDCAHook_', salt);
    bytes memory timeBasedCreationCode =
      abi.encodePacked(type(KSTimeBasedDCAHook).creationCode, abi.encode(routers));
    address timeBasedDCAHook =
      _create3Deploy(keccak256(abi.encodePacked(timeBasedSalt)), timeBasedCreationCode);

    _writeAddress('price-based-dca-hook', priceBasedDCAHook);
    _writeAddress('time-based-dca-hook', timeBasedDCAHook);

    vm.stopBroadcast();
  }
}
