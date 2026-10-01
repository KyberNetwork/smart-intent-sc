# KSSmartIntent

KSSmartIntent is a signed-intent execution system for automation actions.
A user-controlled `mainAddress` defines an intent, delegates execution rights to a delegated key, and allows approved action contracts to run only when the signed action and hook validation match the original intent.

The protocol is built around one router and a set of intent-specific hooks:

- [`KSSmartIntentRouter`](docs/src/src/KSSmartIntentRouter.sol/contract.KSSmartIntentRouter.md) owns the intent lifecycle, EIP-712 hashing, signature checks, nonce consumption, token collection, fee settlement, and action dispatch.
- Hooks implement the business rules for each intent type. A hook can validate action data with [`beforeExecution`](docs/src/src/interfaces/hooks/IKSSmartIntentHook.sol/interface.IKSSmartIntentHook.md#beforeexecution), snapshot state, validate the action result with [`afterExecution`](docs/src/src/interfaces/hooks/IKSSmartIntentHook.sol/interface.IKSSmartIntentHook.md#afterexecution), and return output and fee settlement data.
- Action contracts are external execution targets such as swap routers, zap routers, allowance hubs, or forwarded contracts. The router only calls contracts with [`ACTION_CONTRACT_ROLE`](docs/src/src/KSSmartIntentStorage.sol/abstract.KSSmartIntentStorage.md#action_contract_role).

## Protocol Flow

### 1. Delegate an Intent

The `mainAddress` calls [`delegate(IntentData)`](docs/src/src/KSSmartIntentRouter.sol/contract.KSSmartIntentRouter.md#delegate) to register an intent.

During delegation, the router:

- checks that `msg.sender` is the intent `mainAddress`;
- checks that the intent has not already been delegated or revoked;
- records the intent status as `DELEGATED`;
- stores the ERC20 allowance budget for the intent;
- applies optional ERC20 and ERC721 permit data included in [`TokenData`](docs/src/src/types/TokenData.sol/struct.TokenData.md).

An intent can also be used in one transaction through [`executeWithSignedIntent(...)`](docs/src/src/KSSmartIntentRouter.sol/contract.KSSmartIntentRouter.md#executewithsignedintent).
In that flow, the router validates the `mainAddress` signature, delegates the intent, and immediately executes the action.

### 2. Execute an Action

Anyone can submit [`execute(...)`](docs/src/src/KSSmartIntentRouter.sol/contract.KSSmartIntentRouter.md#execute), but the action must be authorized by the delegated key and a guardian.

The router:

- hashes [`ActionWitness`](docs/src/src/types/ActionWitness.sol/struct.ActionWitness.md) using the `KSSmartIntentRouter` EIP-712 domain;
- validates the delegated-key signature, either as an ECDSA address or through the configured `IERC7913SignatureVerifier`;
- validates the guardian signature unless the guardian is the direct caller;
- checks the action deadline and consumes the unordered action nonce;
- calls [`hook.beforeExecution(...)`](docs/src/src/interfaces/hooks/IKSSmartIntentHook.sol/interface.IKSSmartIntentHook.md#beforeexecution);
- collects the selected ERC20 and ERC721 inputs from the `mainAddress`;
- calls the selected action contract and selector;
- calls [`hook.afterExecution(...)`](docs/src/src/interfaces/hooks/IKSSmartIntentHook.sol/interface.IKSSmartIntentHook.md#afterexecution);
- settles returned tokens and post-execution fees.

[`ActionData.actionSelectorId`](docs/src/src/types/ActionData.sol/struct.ActionData.md) selects the action contract and selector from the arrays embedded in the original intent.
Known Kyber swap, zap, and allowance-hub selectors are called directly.
Other selectors are routed through the configured forwarder.

### 3. Revoke an Intent

The `mainAddress` can call [`revoke(IntentData)`](docs/src/src/KSSmartIntentRouter.sol/contract.KSSmartIntentRouter.md#revoke) at any time.
Revocation sets the intent status to `REVOKED`; no in-scope router write resets that intent back to `NOT_DELEGATED`.

## Core Data Model

[`IntentData`](docs/src/src/types/IntentData.sol/struct.IntentData.md) is the user-level instruction:

- [`coreData`](docs/src/src/types/IntentCoreData.sol/struct.IntentCoreData.md): main address, delegated key, optional signature verifier, allowed action contracts/selectors, hook address, and hook-level intent data.
- [`tokenData`](docs/src/src/types/TokenData.sol/struct.TokenData.md): ERC20 and ERC721 assets that may be collected during execution, including optional permit payloads.
- `extraData`: additional intent-level payload for integrations.

[`ActionData`](docs/src/src/types/ActionData.sol/struct.ActionData.md) is the per-execution instruction:

- `erc20Ids` and `erc20Amounts`: selected ERC20 entries from the intent and the amount to spend for this action.
- `erc721Ids`: selected ERC721 entries from the intent.
- [`feeInfo`](docs/src/src/types/FeeInfo.sol/struct.FeeInfo.md): protocol recipient and partner fee configuration.
- `approvalFlags`: per-token approval behavior before calling the action.
- `actionSelectorId`: index into the intent action contract and selector arrays.
- `actionCalldata`: calldata forwarded to the selected action selector.
- `hookActionData`: hook-specific action payload.
- `deadline`: latest timestamp for execution.
- `nonce`: unordered nonce consumed for this intent.

## Contract Layout

| Area | Contracts | Responsibility |
| --- | --- | --- |
| Router core | [`KSSmartIntentRouter`](docs/src/src/KSSmartIntentRouter.sol/contract.KSSmartIntentRouter.md), [`KSSmartIntentRouterAccounting`](docs/src/src/KSSmartIntentRouterAccounting.sol/abstract.KSSmartIntentRouterAccounting.md), [`KSSmartIntentRouterNonces`](docs/src/src/KSSmartIntentRouterNonces.sol/abstract.KSSmartIntentRouterNonces.md), [`KSSmartIntentStorage`](docs/src/src/KSSmartIntentStorage.sol/abstract.KSSmartIntentStorage.md), [`KSSmartIntentHasher`](docs/src/src/KSSmartIntentHasher.sol/contract.KSSmartIntentHasher.md) | Intent lifecycle, signatures, nonces, token collection, action dispatch, and typed-data hashing |
| Hook bases | [`BaseHook`](docs/src/src/hooks/base/BaseHook.sol/abstract.BaseHook.md), [`BaseStatefulHook`](docs/src/src/hooks/base/BaseStatefulHook.sol/abstract.BaseStatefulHook.md), [`BaseConditionalHook`](docs/src/src/hooks/base/BaseConditionalHook.sol/abstract.BaseConditionalHook.md), [`BaseTickBasedRemoveLiquidityHook`](docs/src/src/hooks/base/BaseTickBasedRemoveLiquidityHook.sol/abstract.BaseTickBasedRemoveLiquidityHook.md) | Shared hook interface, router allowlists, condition evaluation, and liquidity-removal validation |
| Conditional swap | [`KSConditionalSwapHook`](docs/src/src/hooks/swap/KSConditionalSwapHook.sol/contract.KSConditionalSwapHook.md) | Repeated swaps bounded by time, price, amount, fee, and execution-count conditions |
| Remove liquidity | [`KSRemoveLiquidityUniswapV3Hook`](docs/src/src/hooks/remove-liq/KSRemoveLiquidityUniswapV3Hook.sol/contract.KSRemoveLiquidityUniswapV3Hook.md), [`KSRemoveLiquidityUniswapV4Hook`](docs/src/src/hooks/remove-liq/KSRemoveLiquidityUniswapV4Hook.sol/contract.KSRemoveLiquidityUniswapV4Hook.md), [`KSRemoveLiquidityPancakeV4CLHook`](docs/src/src/hooks/remove-liq/KSRemoveLiquidityPancakeV4CLHook.sol/contract.KSRemoveLiquidityPancakeV4CLHook.md) | Position snapshots, tick and liquidity checks, fee bounds, and output validation |
| Zap-out | [`KSZapOutUniswapV2Hook`](docs/src/src/hooks/zap-out/KSZapOutUniswapV2Hook.sol/contract.KSZapOutUniswapV2Hook.md), [`KSZapOutUniswapV3Hook`](docs/src/src/hooks/zap-out/KSZapOutUniswapV3Hook.sol/contract.KSZapOutUniswapV3Hook.md), [`KSZapOutUniswapV4Hook`](docs/src/src/hooks/zap-out/KSZapOutUniswapV4Hook.sol/contract.KSZapOutUniswapV4Hook.md) | LP or position exit validation, price bounds, and min-rate checks |
| Typed data and helpers | [`ActionData`](docs/src/src/types/ActionData.sol/struct.ActionData.md), [`ActionWitness`](docs/src/src/types/ActionWitness.sol/struct.ActionWitness.md), [`IntentData`](docs/src/src/types/IntentData.sol/struct.IntentData.md), [`IntentCoreData`](docs/src/src/types/IntentCoreData.sol/struct.IntentCoreData.md), [`TokenData`](docs/src/src/types/TokenData.sol/struct.TokenData.md), [`ERC20Data`](docs/src/src/types/ERC20Data.sol/struct.ERC20Data.md), [`ERC721Data`](docs/src/src/types/ERC721Data.sol/struct.ERC721Data.md), [`FeeInfo`](docs/src/src/types/FeeInfo.sol/struct.FeeInfo.md), [`ConditionTree`](docs/src/src/types/ConditionTree.sol/struct.ConditionTree.md), [`HookLibrary`](docs/src/src/libraries/HookLibrary.sol/library.HookLibrary.md), [`BitMask`](docs/src/src/libraries/BitMask.sol/constants.BitMask.md) | EIP-712 payloads, fee splitting, condition-tree evaluation, hook return validation, and bitmap helpers |

## Roles and Operations

The router constructor receives:

- `initialAdmin`;
- `initialGuardians`;
- `initialRescuers`;
- `initialActionContracts`;
- `_forwarder`.

Operational roles:

- `DEFAULT_ADMIN_ROLE`: manages role membership, updates the forwarder, transfers ownership, and unpauses the router.
- `KSRoles.GUARDIAN_ROLE`: signs or submits actions and can pause the router.
- `KSRoles.RESCUER_ROLE`: rescues stuck ERC20, ERC721, or ERC1155 assets through inherited management functions.
- [`ACTION_CONTRACT_ROLE`](docs/src/src/KSSmartIntentStorage.sol/abstract.KSSmartIntentStorage.md#action_contract_role): marks contracts that the router may call as action targets.

`pause()` blocks delegation and execution paths.
[`revoke()`](docs/src/src/KSSmartIntentRouter.sol/contract.KSSmartIntentRouter.md#revoke) remains available to the `mainAddress`.

## Hook Families

Hooks are selected by [`IntentCoreData.hook`](docs/src/src/types/IntentCoreData.sol/struct.IntentCoreData.md) and receive two layers of signed hook-specific data:

- `intentData.coreData.hookIntentData`: long-lived configuration signed as part of the intent.
- `actionData.hookActionData`: per-execution input signed as part of the action.

The router calls hooks through [`IKSSmartIntentHook`](docs/src/src/interfaces/hooks/IKSSmartIntentHook.sol/interface.IKSSmartIntentHook.md).
[`beforeExecution`](docs/src/src/interfaces/hooks/IKSSmartIntentHook.sol/interface.IKSSmartIntentHook.md#beforeexecution) validates the action before token collection and can return pre-action fees.
[`afterExecution`](docs/src/src/interfaces/hooks/IKSSmartIntentHook.sol/interface.IKSSmartIntentHook.md#afterexecution) validates the result and can return output settlement data.
[`HookLibrary`](docs/src/src/libraries/HookLibrary.sol/library.HookLibrary.md) checks returned array lengths before settlement continues.

### Base Hooks

The base hook contracts keep shared behavior out of each intent-specific hook.

#### BaseHook

Each hook starts from [`BaseHook`](docs/src/src/hooks/base/BaseHook.sol/abstract.BaseHook.md).
It provides the common hook interface shape and requires the hook to declare its expected token inputs through `checkTokenLengths(...)`.
This keeps token-shape rules close to the hook: swap hooks can require ERC20 input, while position hooks can require an ERC721 NFT.

#### BaseStatefulHook

[`BaseStatefulHook`](docs/src/src/hooks/base/BaseStatefulHook.sol/abstract.BaseStatefulHook.md) is for hooks that keep contract state.
It adds a constructor-defined router allowlist so state updates only come from approved routers.
[`KSConditionalSwapHook`](docs/src/src/hooks/swap/KSConditionalSwapHook.sol/contract.KSConditionalSwapHook.md) uses this because it stores per-intent swap execution counts.

#### BaseConditionalHook

[`BaseConditionalHook`](docs/src/src/hooks/base/BaseConditionalHook.sol/abstract.BaseConditionalHook.md) is for hooks that need reusable condition checks.
It evaluates signed conditions such as time windows, pool-price ranges, and yield thresholds.
It does this through [`ConditionTree`](docs/src/src/types/ConditionTree.sol/struct.ConditionTree.md), represented as an array of [`Node`](docs/src/src/types/ConditionTree.sol/struct.Node.md) values and usually evaluated from index `0`.
Each node is either a leaf containing a [`Condition`](docs/src/src/types/ConditionTree.sol/struct.Condition.md), or a branch that combines child indexes with [`AND` or `OR`](docs/src/src/types/ConditionTree.sol/enum.OperationType.md).

Supported leaf condition types are:

- [`TimeCondition`](docs/src/src/hooks/base/BaseConditionalHook.sol/struct.TimeCondition.md): timestamp window.
- [`PriceCondition`](docs/src/src/hooks/base/BaseConditionalHook.sol/struct.PriceCondition.md): min/max pool price.
- [`YieldCondition`](docs/src/src/hooks/base/BaseConditionalHook.sol/struct.YieldCondition.md): generated fees compared with a target yield.

Builders should provide an acyclic tree with valid child indexes.
Leaf `data` is ABI-encoded for the selected condition type, while `additionalData` is supplied by the hook from current pool or position state.

#### BaseTickBasedRemoveLiquidityHook

[`BaseTickBasedRemoveLiquidityHook`](docs/src/src/hooks/base/BaseTickBasedRemoveLiquidityHook.sol/abstract.BaseTickBasedRemoveLiquidityHook.md) builds on `BaseConditionalHook` for concentrated-liquidity positions.
It centralizes the shared remove-liquidity workflow: selected NFT matching, liquidity-delta validation, max-fee checks, unclaimed-fee handling, native/WETH output adjustment, and token0/token1 settlement.
The Uniswap V3, Uniswap V4, and PancakeSwap V4 CL hooks only need to provide the pool-specific position reads and amount calculations.

### Hook Summary

| Family | Contracts | Input shape | What the hook validates |
| --- | --- | --- | --- |
| Conditional swap | [`KSConditionalSwapHook`](docs/src/src/hooks/swap/KSConditionalSwapHook.sol/contract.KSConditionalSwapHook.md) | One ERC20 input | Selected source/destination pair, recipient, source/destination fee limits, time/amount/price windows, and per-condition execution limits |
| Remove liquidity | [`KSRemoveLiquidityUniswapV3Hook`](docs/src/src/hooks/remove-liq/KSRemoveLiquidityUniswapV3Hook.sol/contract.KSRemoveLiquidityUniswapV3Hook.md), [`KSRemoveLiquidityUniswapV4Hook`](docs/src/src/hooks/remove-liq/KSRemoveLiquidityUniswapV4Hook.sol/contract.KSRemoveLiquidityUniswapV4Hook.md), [`KSRemoveLiquidityPancakeV4CLHook`](docs/src/src/hooks/remove-liq/KSRemoveLiquidityPancakeV4CLHook.sol/contract.KSRemoveLiquidityPancakeV4CLHook.md) | One ERC721 position NFT | Selected position, condition tree, liquidity removal amount, max fee bounds, recipient, and token0/token1 output settlement |
| Zap-out | [`KSZapOutUniswapV2Hook`](docs/src/src/hooks/zap-out/KSZapOutUniswapV2Hook.sol/contract.KSZapOutUniswapV2Hook.md), [`KSZapOutUniswapV3Hook`](docs/src/src/hooks/zap-out/KSZapOutUniswapV3Hook.sol/contract.KSZapOutUniswapV3Hook.md), [`KSZapOutUniswapV4Hook`](docs/src/src/hooks/zap-out/KSZapOutUniswapV4Hook.sol/contract.KSZapOutUniswapV4Hook.md) | V2 uses one ERC20 LP token; V3/V4 use one ERC721 position NFT | Selected LP or position, price bounds, minimum output rate, recipient, and output balance delta |

### Conditional Swap

[`KSConditionalSwapHook`](docs/src/src/hooks/swap/KSConditionalSwapHook.sol/contract.KSConditionalSwapHook.md) is for recurring token swaps such as conditional swap or DCA-style automation.
The intent lists valid source tokens, destination tokens, recipients, and swap condition sets.
Each action selects one path and fee setting.
The hook tracks execution counts in `swapRecord`, so it is deployed with the router allowlist from `script/config/router.json`.

### Remove Liquidity

The remove-liquidity hooks support Uniswap V3, Uniswap V4, and PancakeSwap V4 concentrated-liquidity positions.
The intent lists the permitted position NFTs, recipient, max fee settings, and condition trees.
Each action selects a position and liquidity amount.
The hook family uses pool-specific adapters to read position state, then validates the resulting liquidity and token0/token1 outputs.

### Zap-Out

The zap-out hooks support Uniswap V2, Uniswap V3, and Uniswap V4 exits.
V2 zap-out works from an ERC20 LP token.
V3 and V4 zap-out work from ERC721 position NFTs.
The intent defines the allowed input, output token, recipient, price bounds, and minimum output rate.
These hooks validate the output balance delta and do not return additional fee settlement data.

## Implementation Properties

- Intent status moves from `NOT_DELEGATED` to `DELEGATED` or `REVOKED`.
- Each unordered nonce bit can be consumed once for a given `intentHash`.
- ERC20 spending is bounded by the per-intent allowance budget stored during delegation.
- Partner fee precision is bounded by [`FEE_DENOMINATOR`](docs/src/src/types/FeeInfo.sol/library.FeeInfoLibrary.md#fee_denominator).
- Stateful hooks use constructor-defined router allowlists.
- Conditional swap execution counts only increase when the new count stays within the signed swap limit.
- Action execution is bounded by the signed action deadline.
- Hook return arrays are length-checked before settlement.
- Action targets must have `ACTION_CONTRACT_ROLE`.

## Local Development

Install dependencies:

```shell
forge install
```

Build:

```shell
forge build
```

Run tests:

```shell
forge test
```

Format:

```shell
forge fmt
```

Generate a gas snapshot:

```shell
forge snapshot
```

## Deployment Scripts

Deployment is handled by two Foundry scripts:

- [`script/DeployRouter.s.sol`](script/DeployRouter.s.sol) deploys [`KSSmartIntentRouter`](docs/src/src/KSSmartIntentRouter.sol/contract.KSSmartIntentRouter.md).
- [`script/DeployHooks.s.sol`](script/DeployHooks.s.sol) deploys one or more hook contracts by name.

Both scripts inherit `BaseScript` from `ks-common-sc`.
Config is read from `script/config/*.json` using the current chain id.
If a config file does not have an entry for the current chain id, the helper falls back to the `"0"` entry.
Address outputs are written back to `script/config/<key>.json` only when the script is run with `--broadcast`.

### Router Deployment

`DeployRouter` deploys the router through CREATE3 with the salt prefix `KSSmartIntentRouter_`.
The current script salt is `260209`.

The router constructor inputs are read from:

| Constructor input | Config file |
| --- | --- |
| `initialAdmin` | `script/config/router-admin.json` |
| `initialGuardians` | `script/config/router-guardians.json` |
| `initialRescuers` | `script/config/router-rescuers.json` |
| `initialActionContracts` | `script/config/action-contracts.json` |
| `_forwarder` | `script/config/forwarder.json` |

The deployed router address is written to `script/config/router.json` under the active chain id.

Dry run:

```shell
forge script script/DeployRouter.s.sol:DeployRouter \
  --rpc-url "$RPC_URL"
```

Broadcast:

```shell
forge script script/DeployRouter.s.sol:DeployRouter \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

### Hook Deployment

`DeployHooks` deploys each requested hook through CREATE3 with the salt format:

```text
<HookContractName>_260205
```

Hook behavior is configured in [`script/config/hook-configs.json`](script/config/hook-configs.json).
Each entry defines:

- `constructorParams`: symbolic constructor inputs resolved by the script.
- `exported`: the config key where the deployed hook address is written.

Supported constructor parameter sources:

- `weth`: reads the wrapped native token from `script/config/weth.json`.
- `routers`: reads the deployed router address from `script/config/router.json` and passes it as a one-item router allowlist.

The current hook script supports either no constructor parameters or one symbolic parameter source.
Adding a hook with multiple constructor parameters requires extending `_getConstructorArgs(...)` in `DeployHooks`.

The configured hooks are:

| Hook | Constructor source | Output config |
| --- | --- | --- |
| `KSRemoveLiquidityPancakeV4CLHook` | `weth` | `script/config/remove-liquidity-pancake-v4cl-hook.json` |
| `KSRemoveLiquidityUniswapV3Hook` | `weth` | `script/config/remove-liquidity-uniswap-v3-hook.json` |
| `KSRemoveLiquidityUniswapV4Hook` | `weth` | `script/config/remove-liquidity-uniswap-v4-hook.json` |
| `KSConditionalSwapHook` | `routers` | `script/config/conditional-swap-hook.json` |
| `KSZapOutUniswapV2Hook` | none | `script/config/zap-out-uniswap-v2-hook.json` |
| `KSZapOutUniswapV3Hook` | none | `script/config/zap-out-uniswap-v3-hook.json` |
| `KSZapOutUniswapV4Hook` | none | `script/config/zap-out-uniswap-v4-hook.json` |

Deploy one hook:

```shell
forge script script/DeployHooks.s.sol:DeployHooks \
  --sig "run(string[])" \
  '["KSConditionalSwapHook"]' \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

Deploy the current hook set:

```shell
forge script script/DeployHooks.s.sol:DeployHooks \
  --sig "run(string[])" \
  '["KSRemoveLiquidityPancakeV4CLHook","KSRemoveLiquidityUniswapV3Hook","KSRemoveLiquidityUniswapV4Hook","KSConditionalSwapHook","KSZapOutUniswapV2Hook","KSZapOutUniswapV3Hook","KSZapOutUniswapV4Hook"]' \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast
```

Deploy the router before hooks that use the `routers` constructor source.
For example, `KSConditionalSwapHook` reads `script/config/router.json` and stores the router as its initial allowlisted router.

### Config Checklist

Before broadcasting, check the active chain id entries for:

- `router-admin.json`;
- `router-guardians.json`;
- `router-rescuers.json`;
- `action-contracts.json`;
- `forwarder.json`;
- `weth.json`, for hooks that use `weth`;
- `router.json`, for hooks that use `routers`.

The CREATE3 deployer defaults to `0xc7c662Fc760FE1d5cB97fd8A68cb43A046da3F7d`.
Add `script/config/create3-deployer.json` only if a chain needs a different deployer.

Fork-backed tests and scripts use the RPC endpoints configured in `foundry.toml`:

```shell
export ETH_NODE_URL=<mainnet_rpc_url>
export BSC_NODE_URL=<bsc_rpc_url>
export RPC_URL=<deployment_rpc_url>
export PRIVATE_KEY=<deployment_private_key>
```

The repository is configured for Solidity `^0.8.0`, Foundry, `via_ir`, and high optimizer runs.
