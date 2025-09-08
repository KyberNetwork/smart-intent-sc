// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';

import 'src/hooks/remove-liq/KSRemoveLiquidityUniswapV3Hook.sol';
import 'src/hooks/remove-liq/KSRemoveLiquidityUniswapV4Hook.sol';
import 'src/hooks/swap/KSPriceBasedDCAHook.sol';
import 'src/hooks/swap/KSTimeBasedDCAHook.sol';

contract DeployHooks is BaseScript {
  string salt = '250813';

  function run() external {
    if (bytes(salt).length == 0) {
      revert('salt is required');
    }

    // address router = _readAddress('router');
    address weth = _readAddress('weth');

    vm.startBroadcast();

    // address[] memory routers = new address[](1);
    // routers[0] = router;

    // // Deploy KSPriceBasedDCAHook using CREATE3
    // string memory priceBasedSalt = string.concat('KSPriceBasedDCAHook_', salt);
    // bytes memory priceBasedCreationCode =
    //   abi.encodePacked(type(KSPriceBasedDCAHook).creationCode, abi.encode(routers));
    // address priceBasedDCAHook =
    //   _create3Deploy(keccak256(abi.encodePacked(priceBasedSalt)), priceBasedCreationCode);

    // // Deploy KSTimeBasedDCAHook using CREATE3
    // string memory timeBasedSalt = string.concat('KSTimeBasedDCAHook_', salt);
    // bytes memory timeBasedCreationCode =
    //   abi.encodePacked(type(KSTimeBasedDCAHook).creationCode, abi.encode(routers));
    // address timeBasedDCAHook =
    //   _create3Deploy(keccak256(abi.encodePacked(timeBasedSalt)), timeBasedCreationCode);

    // Deploy KSRemoveLiquidityUniswapV3Hook using CREATE3
    string memory removeLiqV3Salt = string.concat('KSRemoveLiquidityUniswapV3Hook_', salt);
    bytes memory removeLiqV3CreationCode =
      abi.encodePacked(type(KSRemoveLiquidityUniswapV3Hook).creationCode, abi.encode(weth));
    address removeLiquidityUniswapV3Hook =
      _create3Deploy(keccak256(abi.encodePacked(removeLiqV3Salt)), removeLiqV3CreationCode);

    // Deploy KSRemoveLiquidityUniswapV4Hook using CREATE3
    string memory removeLiqV4Salt = string.concat('KSRemoveLiquidityUniswapV4Hook_', salt);
    bytes memory removeLiqV4CreationCode =
      abi.encodePacked(type(KSRemoveLiquidityUniswapV4Hook).creationCode, abi.encode(weth));
    address removeLiquidityUniswapV4Hook =
      _create3Deploy(keccak256(abi.encodePacked(removeLiqV4Salt)), removeLiqV4CreationCode);

    // _writeAddress('hook-price-based-dca', priceBasedDCAHook);
    // _writeAddress('hook-time-based-dca', timeBasedDCAHook);
    _writeAddress('hook-remove-liquidity-uniswap-v3', removeLiquidityUniswapV3Hook);
    _writeAddress('hook-remove-liquidity-uniswap-v4', removeLiquidityUniswapV4Hook);

    vm.stopBroadcast();
  }
}
