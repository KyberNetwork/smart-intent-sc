# KyberSwap Smart Intent

KyberSwap Smart Intent is a smart-contract layer for delegated, condition-aware
KyberSwap actions. A user signs or directly delegates an intent to a delegated
key, a guardian approves each execution, and the router collects the configured
assets, routes execution through an allowed action contract, and validates the
result through pluggable hooks.

This README focuses on repository architecture, core features, runtime behavior,
data structures, hooks, operational controls, events, errors, and development
workflow.

## Contents

- [Repository Scope](#repository-scope)
- [Architecture](#architecture)
- [Execution Model](#execution-model)
- [Core Contracts](#core-contracts)
- [Intent and Action Data Model](#intent-and-action-data-model)
- [Hooks](#hooks)
- [Fees and Accounting](#fees-and-accounting)
- [Signatures and Nonces](#signatures-and-nonces)
- [Access Control and Operations](#access-control-and-operations)
- [Events](#events)
- [Errors](#errors)
- [Repository Layout](#repository-layout)
- [Configuration Files](#configuration-files)
- [Development](#development)
- [Adding a New Hook or Action](#adding-a-new-hook-or-action)
- [Security Notes](#security-notes)
- [License](#license)

## Repository Scope

This repository contains the on-chain components for delegated smart-intent
execution:

- `KSSmartIntentRouter`, the main router for intent delegation, revocation, and
  execution.
- Intent status, unordered nonce, token allowance, fee, rescue, pause, and role
  management logic.
- EIP-712 hashing for `IntentData` and `ActionWitness`.
- Hook contracts that validate swaps, zap-outs, and remove-liquidity actions.
- Interfaces for KyberSwap action contracts, generic forwarding, Uniswap V2/V3/V4
  and Pancake V4 CL position/pool managers.
- Chain-specific deployment configuration for router, hooks, action contracts,
  WETH addresses, admins, guardians, rescuers, and forwarder.
- Foundry tests covering intent execution, signatures, permits, conditional
  swaps, condition trees, zap-out hooks, remove-liquidity hooks, and simulation
  helpers.

Off-chain infrastructure is expected to prepare `IntentData`, `ActionData`,
typed-data signatures, hook payloads, fee configuration, permit payloads, and
action calldata.

## Architecture

```text
Main address / delegated key / guardian
    |
    | delegate(), execute(), or executeWithSignedIntent()
    v
KSSmartIntentRouter
    |
    | validates intent status, signatures, guardian role, deadline, nonce
    | calls beforeExecution hook
    | collects ERC20/ERC721 assets and fees
    v
Action contract or KSGenericForwarder
    |
    | executes approved KyberSwap action selector
    v
Swap router / Zap router / AllowanceHub / external action
    |
    | returns actionResult
    v
HookLibrary.afterExecution()
    |
    | validates post-action state and collects after-execution fees
    v
Recipient, protocol recipient, partner recipients
```

Important architectural choices:

- **Intent state is keyed by typed-data hash.** The router computes the EIP-712
  intent hash and stores whether that intent is not delegated, delegated, or
  revoked.
- **Execution is two-party plus guardian.** The main address delegates the
  intent. The delegated key authorizes each action witness, and a guardian must
  either call the router or sign the same witness.
- **Actions are allowlisted.** The router only executes action contracts with
  `ACTION_CONTRACT_ROLE`, and each intent contains the exact action contract and
  selector set it permits.
- **Hooks validate context and results.** Hooks return fees and state snapshots
  before execution, then validate balances, price ranges, liquidity, ownership,
  conditions, and post-action fees after execution.
- **Token collection is intent-scoped.** ERC20 intent allowances are stored per
  intent hash and reduced as actions spend them.
- **Some actions bypass the generic forwarder.** Known KyberSwap swap, zap, and
  allowance-hub selectors are called directly; other selectors are routed through
  `KSGenericForwarder`.
- **Fee configs are packed.** Partner recipient, partner fee, and fee mode are
  encoded in `FeeConfig` to keep action payloads compact.

## Execution Model

The main router entry points are:

```solidity
function delegate(IntentData calldata intentData) external;

function revoke(IntentData calldata intentData) external;

function execute(
  IntentData calldata intentData,
  bytes calldata dkSignature,
  address guardian,
  bytes calldata gdSignature,
  ActionData calldata actionData
) external;

function executeWithSignedIntent(
  IntentData calldata intentData,
  bytes calldata maSignature,
  bytes calldata dkSignature,
  address guardian,
  bytes calldata gdSignature,
  ActionData calldata actionData
) external;
```

Delegation flow:

1. The router hashes `IntentData` using `KSSmartIntentHasher` and EIP-712 domain
   `KSSmartIntentRouter` version `1`.
2. `delegate()` requires `msg.sender` to be `intentData.coreData.mainAddress`.
3. `executeWithSignedIntent()` accepts a main-address signature instead, then
   delegates and executes in the same transaction.
4. The router checks that the intent has not already been delegated or revoked.
5. ERC20 allowances are recorded per intent hash, and optional ERC20/ERC721
   permit payloads are executed.
6. `DelegateIntent` is emitted.

Execution flow:

1. The router recomputes the intent hash and requires the intent to be delegated.
2. `actionSelectorId` must point to a contract/selector pair included in the
   intent.
3. `actionData.deadline` must not be expired.
4. `guardian` must have `GUARDIAN_ROLE`.
5. The unordered nonce bit for `(intentHash, actionData.nonce)` is consumed.
6. The delegated key signature is checked against the action witness. If
   `signatureVerifier` is zero, ECDSA/ERC-1271 style checking is used against
   `delegatedKey.decodeAddress()`. Otherwise, the configured ERC-7913 verifier
   validates `delegatedKey`.
7. The guardian signature is checked unless the guardian is `msg.sender`.
8. `HookLibrary.beforeExecution()` calls the intent hook and receives
   per-input-token fee amounts plus opaque `beforeExecutionData`.
9. The router checks that the selected action contract has
   `ACTION_CONTRACT_ROLE`.
10. ERC20/ERC721 assets are collected from the main address, optional approvals
    are set, and before-execution fees are distributed.
11. The action selector and action calldata are called either directly on the
    action contract or via the configured forwarder.
12. `HookLibrary.afterExecution()` validates post-action state and distributes
    after-execution fees if the hook returns any.
13. `ExecuteIntent` is emitted with the intent hash, action data, and raw action
    result.

Revocation flow:

1. `revoke()` requires `msg.sender` to be the intent main address.
2. The intent hash is marked `REVOKED`.
3. Future execution attempts revert with `IntentRevoked`.

## Core Contracts

| File | Purpose |
| --- | --- |
| `src/KSSmartIntentRouter.sol` | Main router. Handles delegation, revocation, execution, signature checks, guardian checks, action selection, direct-vs-forwarded action calls, and EIP-712 domain separator exposure. |
| `src/KSSmartIntentRouterAccounting.sol` | Token accounting. Stores ERC20 intent allowances, processes permits, collects ERC20/ERC721 assets, applies approvals, distributes fees, supports ERC721 receipt, and inherits pause/rescue management. |
| `src/KSSmartIntentRouterNonces.sol` | Unordered nonce bitmap per intent hash. Each nonce maps to one bit and can be consumed once. |
| `src/KSSmartIntentStorage.sol` | Shared storage for intent statuses, forwarder address, and `ACTION_CONTRACT_ROLE`. |
| `src/KSSmartIntentHasher.sol` | Pure hashing helper for `IntentData` and `ActionWitness`. |
| `src/libraries/HookLibrary.sol` | Router-side hook adapter. Calls `beforeExecution` and `afterExecution`, checks returned array lengths, and performs after-execution token return and fee collection. |
| `src/types/*.sol` | EIP-712 data structures, packed fee config helpers, token collection helpers, and condition-tree evaluation. |
| `src/hooks/*` | Hook implementations for conditional swaps, zap-out validation, and tick-based remove-liquidity validation. |

## Intent and Action Data Model

### `IntentData`

`IntentData` is the signed or delegated envelope for an intent.

```solidity
struct IntentData {
  IntentCoreData coreData;
  TokenData tokenData;
  bytes extraData;
}
```

- `coreData`: main account, delegated key, allowed action contracts/selectors,
  hook, and hook-level intent payload.
- `tokenData`: ERC20 and ERC721 assets that the intent can spend.
- `extraData`: opaque intent metadata included in the intent hash.

### `IntentCoreData`

```solidity
struct IntentCoreData {
  address mainAddress;
  address signatureVerifier;
  bytes delegatedKey;
  address[] actionContracts;
  bytes4[] actionSelectors;
  address hook;
  bytes hookIntentData;
}
```

- `mainAddress`: user account that owns the intent and source assets.
- `signatureVerifier`: optional ERC-7913 signature verifier. If zero, the
  delegated key is decoded as an address and checked with OpenZeppelin
  `SignatureChecker`.
- `delegatedKey`: delegated signer or verifier-specific key material.
- `actionContracts` and `actionSelectors`: allowed action surface for this
  intent. Arrays must have matching length.
- `hook`: contract that implements `IKSSmartIntentHook`.
- `hookIntentData`: hook-specific validation payload.

### `TokenData`

```solidity
struct TokenData {
  ERC20Data[] erc20Data;
  ERC721Data[] erc721Data;
}
```

`ERC20Data` stores token address, maximum intent amount, and optional permit
payload. `ERC721Data` stores token address, token ID, and optional permit
payload.

During delegation, ERC20 amounts become intent allowances:

```text
erc20Allowances[intentHash][token] = ERC20Data.amount
```

During execution, each ERC20 spend reduces the allowance. If an action attempts
to spend more than the remaining allowance, the router reverts.

### `ActionData`

```solidity
struct ActionData {
  uint256[] erc20Ids;
  uint256[] erc20Amounts;
  uint256[] erc721Ids;
  FeeInfo feeInfo;
  uint256 approvalFlags;
  uint256 actionSelectorId;
  bytes actionCalldata;
  bytes hookActionData;
  bytes extraData;
  uint256 deadline;
  uint256 nonce;
}
```

- `erc20Ids` and `erc721Ids` reference entries in `IntentData.tokenData`.
- `erc20Amounts` are the amounts to spend for the selected ERC20 IDs.
- `feeInfo` configures protocol and partner fee distribution.
- `approvalFlags` is a bitmap. Bits first apply to ERC20 entries, then ERC721
  entries. A set bit grants approval to the action contract.
- `actionSelectorId` selects a contract/selector pair from `IntentCoreData`.
- `actionCalldata` is appended after the selected selector and sent to the action
  contract.
- `hookActionData` is hook-specific per-action payload.
- `deadline` limits action freshness.
- `nonce` is an unordered nonce consumed from the intent bitmap.

### `ActionWitness`

Each execution is authorized by signing:

```solidity
struct ActionWitness {
  bytes32 intentHash;
  ActionData actionData;
}
```

This binds the delegated-key and guardian approvals to one intent and one exact
action payload.

### `FeeConfig` and `FeeInfo`

`FeeConfig` is a packed `uint256`:

```text
1 bit   feeMode
24 bit  partnerFee
160 bit partnerRecipient
```

`partnerFee` uses `1_000_000` precision. The sum of partner fees for one token
must not exceed `1_000_000`.

`FeeInfo` groups fee configs:

```solidity
struct FeeInfo {
  address protocolRecipient;
  FeeConfig[][] partnerFeeConfigs;
}
```

## Hooks

All hooks implement:

```solidity
function beforeExecution(
  bytes32 intentHash,
  IntentData calldata intentData,
  ActionData calldata actionData
) external returns (uint256[] memory fees, bytes memory beforeExecutionData);

function afterExecution(
  bytes32 intentHash,
  IntentData calldata intentData,
  bytes calldata beforeExecutionData,
  bytes calldata actionResult
) external returns (
  address[] memory tokens,
  uint256[] memory fees,
  uint256[] memory amounts,
  address recipient
);
```

The router treats hooks as trusted validation modules. A hook can:

- Reject invalid token selections before assets are collected.
- Compute before-execution fees for source tokens.
- Snapshot balances, ownership, liquidity, pool price, or condition inputs.
- Validate action output after execution.
- Return output-token fees and user-returned amounts for after-execution fee
  distribution.

### Hook Contracts

| Hook | Purpose |
| --- | --- |
| `BaseHook` | Base interface adapter and `InvalidTokenData` check surface. |
| `BaseStatefulHook` | Adds router allowlisting for hooks that store execution state. |
| `BaseConditionalHook` | Evaluates condition trees with time-based, price-based, and yield-based leaf conditions. |
| `BaseTickBasedRemoveLiquidityHook` | Shared remove-liquidity validation for concentrated-liquidity NFT positions. Checks ERC721 data, owner, liquidity delta, output amounts, unclaimed fees, max fees, WETH/native adjustment, and emits `LiquidityRemoved`. |
| `KSConditionalSwapHook` | Validates recurring/conditional ERC20 swaps. Enforces source token, amount range, time range, max source/destination fees, price range, and per-condition swap limits. |
| `KSZapOutUniswapV2Hook` | Validates Uniswap V2-style LP zap-out by checking LP token, reserve-derived price range, recipient balance delta, and minimum output rate. |
| `KSZapOutUniswapV3Hook` | Validates Uniswap V3 NFT zap-out by checking NFT identity, pool price range, liquidity decrease, residual ownership, output balance delta, and minimum output per liquidity. |
| `KSZapOutUniswapV4Hook` | Validates Uniswap V4 NFT zap-out by checking NFT identity, pool price range, position liquidity decrease, residual ownership, output balance delta, and minimum output per liquidity. |
| `KSRemoveLiquidityUniswapV3Hook` | Tick-based remove-liquidity hook for Uniswap V3 position NFTs. Computes expected token amounts and unclaimed fees from position manager and pool fee-growth data. |
| `KSRemoveLiquidityUniswapV4Hook` | Tick-based remove-liquidity hook for Uniswap V4 position NFTs. Uses `StateLibrary` and pool manager storage reads to compute position values. |
| `KSRemoveLiquidityPancakeV4CLHook` | Tick-based remove-liquidity hook for Pancake V4 CL position NFTs. Reads CL pool state, tick fee growth, and position data. |

### Condition Trees

Remove-liquidity hooks use `ConditionTree`:

```solidity
struct Condition {
  ConditionType conditionType;
  bytes data;
}

struct Node {
  OperationType operationType;
  Condition condition;
  uint256[] childrenIndexes;
}

struct ConditionTree {
  Node[] nodes;
  bytes[] additionalData;
}
```

Supported condition types in `BaseConditionalHook`:

- `TIME_BASED`: block timestamp must be between `startTimestamp` and
  `endTimestamp`.
- `PRICE_BASED`: current price must be between `minPrice` and `maxPrice`.
- `YIELD_BASED`: generated fees converted to token0 terms must meet or exceed
  `targetYield` with `1_000_000` precision.

The tree supports `AND` and `OR` internal nodes. The evaluator assumes the tree
is acyclic and that child indexes point to valid nodes.

## Fees and Accounting

### Before-Execution Fees

Hooks return one fee amount for each ERC20 input used by the action. During
collection:

1. The router transfers `amount - fee` from the main address to the action
   contract or forwarder.
2. If the approval flag for that asset is set, the router or forwarder approves
   the action contract.
3. `FeeInfoLibrary.computeFees()` splits the fee between the protocol and
   partners.
4. Partner fees are either transferred directly to the partner recipient or added
   to the protocol recipient amount when `feeMode` is true.
5. `RecordVolumeAndFees(..., beforeExecution = true, totalAmount = amount)` is
   emitted.

### After-Execution Fees

If a hook returns output tokens, fees, amounts, and a recipient after execution:

1. The router sends each `amounts[i]` from itself to `recipient`.
2. It splits each `fees[i]` using `partnerFeeConfigs[i]`.
3. It emits `RecordVolumeAndFees(..., beforeExecution = false, totalAmount =
   amounts[i] + fees[i])`.

### Forwarder Behavior

The router calls these action selectors directly:

- `IKSSwapRouterV2.swap`
- `IKSSwapRouterV2.swapSimpleMode`
- `IKSSwapRouterV3.swap`
- `IKSZapRouter.zap`
- `IKSAllowanceHub.permitTransferAndExecute`

Other allowed selectors are executed via the configured `IKSGenericForwarder`.
When a forwarder is used, assets are transferred to the forwarder and approvals
are set through forwarded token calls.

## Signatures and Nonces

The EIP-712 domain is:

```text
name:    KSSmartIntentRouter
version: 1
```

Signature checks:

- Main-address signature: required only by `executeWithSignedIntent`.
- Delegated-key signature: required unless `msg.sender` is the delegated address
  in the default signature mode.
- Guardian signature: required unless `msg.sender` is the guardian address.
- ERC-7913 mode: used when `IntentCoreData.signatureVerifier` is non-zero.

Nonces are unordered bitmaps:

```text
wordPos = nonce >> 8
bitPos  = uint8(nonce)
```

Using the same nonce twice for the same intent hash reverts with
`NonceAlreadyUsed`.

## Access Control and Operations

The router inherits management utilities from `ks-common-sc`.

| Role | Meaning |
| --- | --- |
| `DEFAULT_ADMIN_ROLE` | Can update the forwarder, grant/revoke roles, transfer admin ownership, unpause, and perform admin-only operations inherited from OpenZeppelin access control. |
| `GUARDIAN_ROLE` | Required for action execution. A guardian can call execution directly or sign the action witness. Guardians can also pause through inherited management logic. |
| `RESCUER_ROLE` | Can rescue ERC20, ERC721, and ERC1155 assets. The default admin can also use rescuer-only recovery paths through inherited management logic. |
| `ACTION_CONTRACT_ROLE` | Marks action contracts the router is allowed to call. |

Operational functions:

- `updateForwarder(address)`: updates the generic forwarder.
- `pause()`: pauses delegation and execution. Callable by guardian or default
  admin.
- `unpause()`: unpauses. Callable by default admin.
- `batchGrantRole(bytes32,address[])`: grants a role to multiple accounts.
- `batchRevokeRole(bytes32,address[])`: revokes a role from multiple accounts.
- `transferOwnership(address)`: moves `DEFAULT_ADMIN_ROLE`.
- `rescueERC20s`, `rescueERC721s`, `rescueERC1155s`: rescue stuck assets.

## Events

### Smart Intent Events

| Event | Emitted by | Explanation |
| --- | --- | --- |
| `UpdateForwarder(address newForwarder)` | `IKSSmartIntentRouter` | The generic forwarder address was updated. |
| `DelegateIntent(address indexed mainAddress, bytes delegatedKey, IntentData intentData)` | `IKSSmartIntentRouter` | An intent was delegated and ERC20 allowances were recorded. |
| `RevokeIntent(bytes32 indexed intentHash)` | `IKSSmartIntentRouter` | An intent was revoked by its main address. |
| `ExecuteIntent(bytes32 indexed intentHash, ActionData actionData, bytes actionResult)` | `IKSSmartIntentRouter` | An action was executed for a delegated intent. |
| `UseNonce(bytes32 indexed intentHash, uint256 nonce)` | `IKSSmartIntentRouter` | An unordered nonce bit was consumed for an intent. |
| `RecordVolumeAndFees(address indexed token, address indexed protocolRecipient, FeeConfig[] partnerFeeConfigs, uint256 protocolFeeAmount, uint256[] partnersFeeAmounts, bool beforeExecution, uint256 totalAmount)` | `IKSSmartIntentRouter` | Fee and volume accounting record for source-token or output-token fees. |

### Hook Events

| Event | Emitted by | Explanation |
| --- | --- | --- |
| `LiquidityRemoved(address nftAddress, uint256 nftId, uint256 liquidity)` | `BaseTickBasedRemoveLiquidityHook` | A remove-liquidity hook validated a successful liquidity reduction. |

### Management Events

| Event | Emitted by | Explanation |
| --- | --- | --- |
| `RescueERC20s(address[] tokens, uint256[] amounts, address recipient)` | `ManagementRescuable` | ERC20 funds were rescued from the router. |
| `RescueERC721s(IERC721[] tokens, uint256[] tokenIds, address recipient)` | `ManagementRescuable` | ERC721 tokens were rescued from the router. |
| `RescueERC1155s(IERC1155[] tokens, uint256[] tokenIds, uint256[] amounts, address recipient)` | `ManagementRescuable` | ERC1155 tokens were rescued from the router. |
| `Paused(address account)` | OpenZeppelin `Pausable` | Router was paused. |
| `Unpaused(address account)` | OpenZeppelin `Pausable` | Router was unpaused. |
| `RoleGranted(bytes32 role, address account, address sender)` | OpenZeppelin access control | A role was granted. |
| `RoleRevoked(bytes32 role, address account, address sender)` | OpenZeppelin access control | A role was revoked. |
| `DefaultAdminTransferScheduled(address newAdmin, uint48 acceptSchedule)` | OpenZeppelin default-admin rules | Default admin transfer was scheduled. |
| `DefaultAdminTransferCanceled()` | OpenZeppelin default-admin rules | Default admin transfer was canceled. |
| `DefaultAdminDelayChangeScheduled(uint48 newDelay, uint48 effectSchedule)` | OpenZeppelin default-admin rules | Default admin delay change was scheduled. |
| `DefaultAdminDelayChangeCanceled()` | OpenZeppelin default-admin rules | Default admin delay change was canceled. |

### External Protocol Interface Events

These events are declared in imported protocol interfaces and may be emitted by
external protocols, not by the smart-intent router itself.

| Interface | Events | Explanation |
| --- | --- | --- |
| `ICLPositionManager` | `MintPosition`, `ModifyLiquidity` | Pancake V4 CL position lifecycle and liquidity changes. |
| `ICLPoolManager` | `DynamicLPFeeUpdated`, `ModifyLiquidity`, `Swap`, `Donate` | Pancake V4 CL pool fee, liquidity, swap, and donation events. |

## Errors

### Router and Accounting Errors

| Error | Thrown by | Explanation |
| --- | --- | --- |
| `InvalidFeeConfig()` | `IKSSmartIntentRouter`, `FeeInfoLibrary` | Partner fee precision exceeds `1_000_000` for a token. |
| `NotMainAddress()` | `KSSmartIntentRouter` | Caller is not the intent main address for delegation or revocation. |
| `ActionExpired()` | `KSSmartIntentRouter` | `actionData.deadline` is earlier than the current block timestamp. |
| `IntentNotDelegated()` | `KSSmartIntentRouter` | Execution was attempted before delegation. |
| `IntentDelegated()` | `KSSmartIntentRouter` | Delegation was attempted for an already delegated intent. |
| `IntentRevoked()` | `KSSmartIntentRouter` | Operation was attempted on a revoked intent. |
| `InvalidMainAddressSignature()` | `KSSmartIntentRouter` | Main-address signature for `executeWithSignedIntent` is invalid. |
| `InvalidDelegatedKeySignature()` | `KSSmartIntentRouter` | Delegated-key signature or ERC-7913 verification failed. |
| `InvalidGuardianSignature()` | `KSSmartIntentRouter` | Guardian signature is invalid when the guardian is not the caller. |
| `InvalidActionSelectorId(uint256 actionSelectorId)` | `KSSmartIntentRouter` | `actionSelectorId` is outside the intent's allowed action arrays. |
| `NonceAlreadyUsed(bytes32 intentHash, uint256 nonce)` | `KSSmartIntentRouterNonces` | The nonce bit was already consumed for this intent. |
| `ERC20InsufficientIntentAllowance(bytes32 intentHash, address token, uint256 allowance, uint256 needed)` | `KSSmartIntentRouterAccounting` | Action tried to spend more of a token than the remaining intent allowance. |
| `InvalidAddress()` | `ks-common-sc/Common` | A required address parameter is zero. |
| `MismatchedArrayLengths()` | `ks-common-sc/Common`, `HookLibrary` | Paired arrays or hook-returned arrays have different lengths. |
| `AccessControlUnauthorizedAccount(address account, bytes32 neededRole)` | OpenZeppelin access control | Caller does not have the required role. |
| `EnforcedPause()` | OpenZeppelin `Pausable` | A paused function was called while the router is paused. |

### Hook Errors

| Error | Thrown by | Explanation |
| --- | --- | --- |
| `InvalidTokenData()` | `BaseHook` and hook modifiers | Action token IDs or counts do not match what the hook expects. |
| `NonWhitelistedRouter(address router)` | `BaseStatefulHook` | Stateful hook was called by a router not in its whitelist. |
| `WrongConditionType()` | `BaseConditionalHook` | Condition type is not `TIME_BASED`, `PRICE_BASED`, or `YIELD_BASED`. |
| `ConditionsNotMet()` | `IKSConditionalHook` | Condition tree evaluated to false. |
| `InvalidNodeIndex()` | `ConditionTreeLibrary` | Condition tree root or child index is out of bounds. |
| `WrongOperationType()` | `ConditionTreeLibrary` | Non-leaf condition node has an unsupported operation type. |
| `InvalidOwner()` | Remove-liquidity and zap-out hooks | NFT owner after execution is not the expected main address when ownership should remain. |
| `InvalidLiquidity()` | `BaseTickBasedRemoveLiquidityHook` | Position liquidity after execution does not equal expected pre-liquidity minus removed liquidity. |
| `NotEnoughOutputAmount()` | `BaseTickBasedRemoveLiquidityHook` | User output after fees is below the minimum implied by max fee bounds. |
| `NotEnoughFeesReceived()` | `BaseTickBasedRemoveLiquidityHook` | Router received less than the expected unclaimed fees. |
| `ExceedMaxFeesPercent()` | `BaseTickBasedRemoveLiquidityHook` | Action fee percentages exceed the intent-level max fees. |
| `InvalidERC721Data()` | `BaseTickBasedRemoveLiquidityHook` | Action ERC721 token address or ID does not match hook validation data. |
| `InvalidTokenIn(address tokenIn, address actualTokenIn)` | `KSConditionalSwapHook` | Selected input token does not match the hook's configured source token. |
| `AmountInMismatch(uint256 amountIn, uint256 actualAmountIn)` | `KSConditionalSwapHook` | Main-address balance delta exceeds the action input amount. |
| `InvalidSwap()` | `KSConditionalSwapHook` | No swap condition matched, or all matching conditions exceeded their swap limit. |
| `InvalidSwapPair()` | `KSZapOutUniswapV2Hook` | Reserved Uniswap V2 zap-out validation error. |
| `BelowMinRate(uint256 inputAmount, uint256 outputAmount, uint256 minRate)` | `KSZapOutUniswapV2Hook` | V2 zap-out output is below the configured minimum rate. |
| `OutsidePriceRange(uint256 priceLower, uint256 priceUpper, uint256 priceCurrent)` | `KSZapOutUniswapV2Hook` | V2 reserve-derived price is outside the configured range. |
| `InvalidZapOutPosition()` | V3/V4 zap-out hooks | Reserved zap-out position validation error. |
| `OutsidePriceRange(uint160 sqrtPLower, uint160 sqrtPUpper, uint160 sqrtPriceX96)` | V3/V4 zap-out hooks | Pool sqrt price is outside the configured range. |
| `GetPositionLiquidityFailed()` | `KSZapOutUniswapV3Hook` | Staticcall to read V3 position liquidity failed. |
| `GetSqrtPriceX96Failed()` | `KSZapOutUniswapV3Hook` | Staticcall to read V3 pool `slot0` failed. |
| `BelowMinRate(uint256 liquidity, uint256 minRate, uint256 outputAmount)` | V3/V4 zap-out hooks | Output amount is below the configured minimum per removed liquidity. |

### External Protocol Interface Errors

These errors are declared in imported external protocol interfaces. They may be
observed when action contracts or hooks call those protocols, but their semantics
belong to the external protocol.

| Interface | Errors |
| --- | --- |
| `IPositionManager` | `NotApproved`, `DeadlinePassed`, `PoolManagerMustBeLocked` |
| `IPoolManager` | `CurrencyNotSettled`, `PoolNotInitialized`, `AlreadyUnlocked`, `ManagerLocked`, `TickSpacingTooLarge`, `TickSpacingTooSmall`, `CurrenciesOutOfOrderOrEqual`, `UnauthorizedDynamicLPFeeUpdate`, `SwapAmountCannotBeZero`, `NonzeroNativeValue`, `MustClearExactPositiveDelta` |
| `ICLPositionManager` | `DeadlinePassed`, `VaultMustBeUnlocked`, `InvalidTokenID`, `NotApproved` |
| `ICLPoolManager` | `PoolNotInitialized`, `CurrenciesInitializedOutOfOrder`, `UnauthorizedDynamicLPFeeUpdate`, `PoolManagerMismatch`, `TickSpacingTooLarge`, `TickSpacingTooSmall`, `PoolPaused`, `SwapAmountCannotBeZero` |

## Repository Layout

```text
src/
  KSSmartIntentRouter.sol             Main smart-intent router
  KSSmartIntentRouterAccounting.sol   Token collection, fee, permit, rescue, pause logic
  KSSmartIntentRouterNonces.sol       Unordered nonce bitmap logic
  KSSmartIntentStorage.sol            Shared router storage and roles
  KSSmartIntentHasher.sol             EIP-712 struct hashing helper
  hooks/
    base/                             Shared hook bases and condition evaluation
    swap/                             Conditional swap hook
    zap-out/                          Uniswap V2/V3/V4 zap-out hooks
    remove-liq/                       Uniswap V3/V4 and Pancake V4 CL remove-liquidity hooks
  interfaces/
    actions/                          KyberSwap action contract interfaces
    hooks/                            Smart-intent hook interfaces
    pancakev4/                        Pancake V4 CL pool and position interfaces
    uniswapv2/                        Uniswap V2 pair interface
    uniswapv3/                        Uniswap V3 pool and position-manager interfaces
    uniswapv4/                        Uniswap V4 pool and position-manager interfaces
  libraries/
    HookLibrary.sol                   Hook adapter and after-execution fee handling
    BitMask.sol                       Bit masks used by packed data helpers
    uniswapv4/                        Tick, liquidity, and state helper libraries
  types/                              Intent, action, token, fee, and condition structs

script/
  DeployRouter.s.sol                  CREATE3 router deployment script
  DeployHooks.s.sol                   CREATE3 hook deployment script
  config/                             Chain-specific operational JSON

test/
  *.t.sol                             Foundry tests and fork tests
  mocks/                              Mock action, hook, DEX, and router harness contracts
  common/                             Test permit helpers
  libraries/                          Test array helpers

lib/
  ks-common-sc/                       KyberSwap common contracts and dependencies
```

## Configuration Files

`script/config` stores chain-specific deployment and operations data.

| File | Purpose |
| --- | --- |
| `router-admin.json` | Initial router admin address. |
| `router-guardians.json` | Initial guardian role addresses. |
| `router-rescuers.json` | Initial rescuer role addresses. |
| `action-contracts.json` | Initial action contracts granted `ACTION_CONTRACT_ROLE`. |
| `forwarder.json` | Generic forwarder address by chain. |
| `router.json` | Deployed smart-intent router address by chain. |
| `weth.json` | Wrapped native token address by chain. |
| `hook-configs.json` | Hook constructor parameter sources and exported config keys. |
| `remove-liquidity-uniswap-v3-hook.json` | Deployed Uniswap V3 remove-liquidity hook addresses. |
| `remove-liquidity-uniswap-v4-hook.json` | Deployed Uniswap V4 remove-liquidity hook addresses. |
| `remove-liquidity-pancake-v4cl-hook.json` | Deployed Pancake V4 CL remove-liquidity hook addresses. |

`foundry.toml` enables optimizer, `via_ir`, FFI, repository read-write file
permissions for scripts, a router-specific compiler profile, formatting rules,
and RPC endpoint environment variables.

## Development

Install dependencies:

```shell
git submodule update --init --recursive
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

Run a focused test:

```shell
forge test --match-contract ConditionalSwap
```

Deploy the router:

```shell
forge script script/DeployRouter.s.sol:DeployRouter \
  --rpc-url <rpc-url> \
  --private-key <private-key> \
  --broadcast
```

Deploy hooks:

```shell
forge script script/DeployHooks.s.sol:DeployHooks \
  --sig "run(string[])" '["KSConditionalSwapHook"]' \
  --rpc-url <rpc-url> \
  --private-key <private-key> \
  --broadcast
```

Deployment scripts use the shared `ks-common-sc` script helpers for reading and
writing `script/config/*.json` values and for CREATE3 deployments.

## Adding a New Hook or Action

Typical hook integration steps:

1. Define hook-specific intent payload and action payload structs.
2. Implement `IKSSmartIntentHook.beforeExecution` to validate selected token
   IDs, decode hook data, snapshot state, and return source-token fees.
3. Implement `IKSSmartIntentHook.afterExecution` to validate output state and
   return output-token fee data when fees are charged after execution.
4. Reuse `BaseHook`, `BaseStatefulHook`, `BaseConditionalHook`, or
   `BaseTickBasedRemoveLiquidityHook` when the new hook matches an existing
   pattern.
5. Add external protocol interfaces under `src/interfaces` if the hook needs
   protocol reads.
6. Add tests for successful execution, signature paths, invalid token data,
   invalid state, fee bounds, and revert cases.
7. Add the hook to `script/config/hook-configs.json` if it is deployed through
   `DeployHooks.s.sol`.

Typical action-contract integration steps:

1. Add or update an action interface under `src/interfaces/actions`.
2. Grant the deployed action contract `ACTION_CONTRACT_ROLE`.
3. Include the action contract and selector in each intent that should be able to
   call it.
4. If the selector should bypass the generic forwarder, update
   `KSSmartIntentRouter._needForwarder`.
5. Add tests that prove token collection, approvals, forwarding mode, hook
   validation, and fee accounting behave as expected.

## Security Notes

- `delegate()` and `revoke()` can only be called by the intent main address.
- `executeWithSignedIntent()` can delegate with a valid main-address signature
  and execute in one transaction.
- Each action must be authorized by the delegated key and guardian.
- Guardian addresses must have `GUARDIAN_ROLE`.
- Action contracts must have `ACTION_CONTRACT_ROLE`.
- Intent action contracts and selectors are fixed inside the signed intent.
- The router is protected by transient reentrancy guard during execution.
- Pausing disables delegation and execution.
- ERC20 spend is capped by per-intent allowances stored at delegation time.
- Unordered nonces prevent replay of the same action witness.
- Hooks are trusted validation modules. A weak hook can weaken the guarantees of
  intents that use it.
- `FeeConfig` totals are checked so partner fees cannot exceed 100% of the fee
  amount for a token.
- ERC20 approval flags can grant maximum allowance to action contracts. Only
  trusted action contracts should be granted `ACTION_CONTRACT_ROLE`.
- Forwarded actions move assets to the generic forwarder before execution; the
  configured forwarder is therefore part of the trusted execution path.
- Remove-liquidity hooks validate ownership, liquidity deltas, fee receipt, and
  minimum received amounts, but they rely on protocol-specific state reads and
  hook payload correctness.
- `rescue*` functions are operational recovery tools controlled by rescuer or
  admin roles.

## License

This repository includes a `LICENSE` file containing GPL-3.0. Some imported
dependencies and Solidity files use their own SPDX identifiers. Check individual
files and the root license before reusing code.
