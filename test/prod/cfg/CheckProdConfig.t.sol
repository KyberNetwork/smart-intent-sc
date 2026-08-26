// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {KSSmartIntentRouter} from 'src/KSSmartIntentRouter.sol';

import {BaseStatefulHook} from 'src/hooks/base/BaseStatefulHook.sol';
import {
  BaseTickBasedRemoveLiquidityHook
} from 'src/hooks/base/BaseTickBasedRemoveLiquidityHook.sol';

import 'ks-common-sc/script/Base.s.sol';

import {stdJson} from 'forge-std/StdJson.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

struct ActionContract {
  address addr;
  string name;
}

contract CheckProdConfig is Test, BaseScript {
  using stdJson for string;

  bytes32 constant ACTION_CONTRACT_ROLE = keccak256('ACTION_CONTRACT_ROLE');
  bytes32 constant GUARDIAN_ROLE = keccak256('GUARDIAN_ROLE');
  bytes32 constant RESCUER_ROLE = keccak256('RESCUER_ROLE');

  uint256 constant FORWARDER_SLOT = 1;

  KSSmartIntentRouter router;
  address admin;
  address forwarder;
  address[] guardians;
  address[] rescuers;
  address[] actionContractAddresses;

  /// @notice Checks every chain the router is deployed to, taken from `router.json`.
  function test_prodConfig() public {
    uint256[] memory chains = _deployedChains('router');
    assertGt(chains.length, 0, 'router.json lists no chains');

    for (uint256 i = 0; i < chains.length; i++) {
      console.log('=== chain %s ===', vm.toString(chains[i]));

      _fork(chains[i]);
      _readFiles();
      _check();
    }
  }

  function _fork(uint256 chainId) internal {
    vm.createSelectFork(_rpcUrl(chainId));

    assertEq(block.chainid, chainId, 'the RPC URL points at a different chain');
  }

  function _readFiles() internal {
    router = KSSmartIntentRouter(payable(_readAddress('router')));
    admin = _readAddress('router-admin');
    forwarder = _readAddress('forwarder');
    guardians = _readAddressArray('router-guardians');
    rescuers = _readAddressArray('router-rescuers');
    ActionContract[] memory entries = actionContracts();
    actionContractAddresses = new address[](entries.length);
    for (uint256 i = 0; i < entries.length; i++) {
      actionContractAddresses[i] = entries[i].addr;
    }
  }

  function _check() internal {
    _checkRouterDeployed();
    _checkRouterRoles();
    _checkActionContractsAreNamed();
    _checkRouterForwarder();
    _checkRouterDomainSeparator();
    _checkRouterOperable();
    _checkHooks();
  }

  function _checkRouterDeployed() private {
    assertGt(address(router).code.length, 0, 'router has no code');
    assertGt(
      vm.computeCreateAddress(address(router), 1).code.length, 0, 'router did not deploy its hasher'
    );
  }

  function _checkRouterRoles() private {
    assertEq(router.defaultAdmin(), admin, 'default admin is not router-admin.json');

    for (uint256 i = 0; i < guardians.length; i++) {
      assertTrue(
        router.hasRole(GUARDIAN_ROLE, guardians[i]),
        string.concat('guardian without GUARDIAN_ROLE: ', vm.toString(guardians[i]))
      );
    }
    for (uint256 i = 0; i < rescuers.length; i++) {
      assertTrue(
        router.hasRole(RESCUER_ROLE, rescuers[i]),
        string.concat('rescuer without RESCUER_ROLE: ', vm.toString(rescuers[i]))
      );
    }
    for (uint256 i = 0; i < actionContractAddresses.length; i++) {
      assertTrue(
        router.hasRole(ACTION_CONTRACT_ROLE, actionContractAddresses[i]),
        string.concat(
          'action without ACTION_CONTRACT_ROLE: ', vm.toString(actionContractAddresses[i])
        )
      );
      assertGt(
        actionContractAddresses[i].code.length,
        0,
        string.concat('action contract has no code: ', vm.toString(actionContractAddresses[i]))
      );
    }
  }

  function _checkActionContractsAreNamed() private {
    ActionContract[] memory entries = actionContracts();

    for (uint256 i = 0; i < entries.length; i++) {
      assertGt(
        bytes(entries[i].name).length,
        0,
        string.concat(
          'action contract ', vm.toString(entries[i].addr), ' has no name in action-contracts.json'
        )
      );
    }
  }

  function _checkRouterForwarder() private {
    address onchain = address(uint160(uint256(vm.load(address(router), bytes32(FORWARDER_SLOT)))));

    assertEq(onchain, forwarder, 'forwarder is not forwarder.json');
    assertGt(onchain.code.length, 0, 'forwarder has no code');
  }

  function _checkRouterDomainSeparator() private {
    bytes32 expected = keccak256(
      abi.encode(
        keccak256(
          'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
        ),
        keccak256(bytes('KSSmartIntentRouter')),
        keccak256(bytes('1')),
        block.chainid,
        address(router)
      )
    );

    assertEq(
      router.DOMAIN_SEPARATOR(),
      expected,
      'DOMAIN_SEPARATOR does not match name/version/chainId/address'
    );
  }

  function _checkRouterOperable() private {
    assertFalse(router.paused(), 'router is paused');

    (address pendingAdmin,) = router.pendingDefaultAdmin();
    assertEq(pendingAdmin, address(0), 'an admin handover is pending');
  }

  function _checkHooks() private {
    string memory json = vm.readFile(string.concat(path, 'hook-configs.json'));
    string[] memory names = vm.parseJsonKeys(json, '$');

    for (uint256 i = 0; i < names.length; i++) {
      string memory exported = json.readString(string.concat('.', names[i], '.exported'));
      if (!_deployedOnThisChain(exported)) {
        console.log('%s: not deployed on this chain', names[i]);
        continue;
      }

      address hook = _readAddress(exported);
      console.log('%s: %s', names[i], vm.toString(hook));

      assertGt(hook.code.length, 0, string.concat(names[i], ' has no code'));
      _checkHookWiring(hook);
    }
  }

  function _checkHookWiring(address hook) private {
    if (_supports(hook, abi.encodeWithSignature('WETH()'))) {
      address weth = BaseTickBasedRemoveLiquidityHook(hook).WETH();

      assertEq(weth, _readAddress('weth'), 'hook WETH() is not weth.json');
      assertGt(weth.code.length, 0, 'hook WETH has no code');
    }

    if (_supports(hook, abi.encodeWithSignature('whitelistedRouters(address)', address(0)))) {
      assertTrue(
        BaseStatefulHook(hook).whitelistedRouters(address(router)),
        'router is not whitelisted on the hook'
      );
    }
  }

  function _supports(address target, bytes memory callData) private view returns (bool ok) {
    (ok,) = target.staticcall(callData);
  }

  function actionContracts() internal view returns (ActionContract[] memory) {
    return abi.decode(
      vm.parseJson(_getJsonString('action-contracts'), _toDotChainId(block.chainid)),
      (ActionContract[])
    );
  }

  function _deployedOnThisChain(string memory name) internal view returns (bool) {
    return _getJsonString(name).keyExists(_toDotChainId(block.chainid));
  }

  function _deployedChains(string memory name) internal view returns (uint256[] memory ids) {
    string[] memory keys = vm.parseJsonKeys(_getJsonString(name), '$');

    ids = new uint256[](keys.length);
    uint256 count;
    for (uint256 i = 0; i < keys.length; i++) {
      uint256 chainId = vm.parseUint(keys[i]);
      if (chainId == 0) continue;
      ids[count++] = chainId;
    }

    assembly ('memory-safe') {
      mstore(ids, count)
    }
  }

  function _rpcUrl(uint256 chainId) internal view returns (string memory url) {
    string memory key = string.concat('RPC_', vm.toString(chainId));

    url = vm.envOr(key, string(''));
    require(bytes(url).length > 0, string.concat(key, ' is not set'));
  }
}
