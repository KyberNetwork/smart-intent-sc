// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';

import 'src/hooks/swap/KSPriceBasedDCAHook.sol';
import 'src/hooks/swap/KSTimeBasedDCAHook.sol';

contract DeployHooks is BaseScript {
  function run() external {
    address router = _readAddress('router');

    vm.startBroadcast();

    address[] memory routers = new address[](1);
    routers[0] = router;

    KSPriceBasedDCAHook priceBasedDCAHook = new KSPriceBasedDCAHook(routers);
    KSTimeBasedDCAHook timeBasedDCAHook = new KSTimeBasedDCAHook(routers);

    _writeAddress('price-based-dca-hook', address(priceBasedDCAHook));
    _writeAddress('time-based-dca-hook', address(timeBasedDCAHook));

    vm.stopBroadcast();
  }
}
