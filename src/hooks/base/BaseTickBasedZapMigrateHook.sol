// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IKSSmartIntentHook} from '../../interfaces/hooks/IKSSmartIntentHook.sol';
import {BaseStatefulHook} from '../base/BaseStatefulHook.sol';

import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

import {ActionData} from '../../types/ActionData.sol';
import {IntentData} from '../../types/IntentData.sol';

import {FixedPoint96} from '../../libraries/uniswapv4/FixedPoint96.sol';

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

abstract contract BaseTickBasedZapMigrateHook is BaseStatefulHook {
  using TokenHelper for address;
  using Math for uint256;

  event ZapMigrated(address nftAddress, uint256 oldNftId, uint256 newNftId);

  error InvalidOwner();
  error ExceedMaxFeesPercent();
  error InvalidERC721Data();
  error InsufficientPositionValue();
  error TooLargeDistanceFromTickBoundaries();
  error TooSmallDistanceFromTickBoundaries();
  error InvalidPoolUniqueId();
  error TooSmallTickRangeLength();
  error TooLargeTickRangeLength();
  error ExceedMaxValueReductionInToken0();
  error ExceedMaxValueReductionInToken1();
  error ExceedMaxValueReductionPerAction();

  /**
   * @notice Data structure for zap migrate validation
   * @param nftAddress The NFT address
   * @param nftId The NFT ID
   * @param minValueInToken0 The min value of the position in token0
   * @param minValueInToken1 The min value of the position in token1
   * @param maxValueReductionPerAction The max value reduction per action (in token0 if price decreases, in token1 if price increases)
   * @param maxDistanceFromLowerTickBeforeMigration The max distance from the lower tick to the current tick before migration
   * @param maxDistanceFromUpperTickBeforeMigration The max distance from the upper tick to the current tick before migration
   * @param minDistanceFromLowerTickAfterMigration The min distance from the lower tick to the current tick after migration
   * @param minDistanceFromUpperTickAfterMigration The min distance from the upper tick to the current tick after migration
   * @param maxFees The max fees for each output token (1e6 = 100%)
   */
  struct ZapMigrateHookData {
    address nftAddress;
    uint256 nftId;
    uint256 minValueInToken0;
    uint256 minValueInToken1;
    uint256 maxValueReductionPerAction;
    int24 maxDistanceFromLowerTickBeforeMigration;
    int24 maxDistanceFromUpperTickBeforeMigration;
    int24 minDistanceFromLowerTickAfterMigration;
    int24 minDistanceFromUpperTickAfterMigration;
    int24 minTickRangeLength;
    int24 maxTickRangeLength;
    uint256[] maxFees;
  }

  /**
   * @notice Data structure for before execution data
   * @param originalNftId The original NFT ID
   * @param poolUniqueId The unique ID of the pool
   * @param amount0Before The amount of token0 of the position before execution
   * @param amount1Before The amount of token1 of the position before execution
   * @param balance0Before The balance of token0 of the router before execution
   * @param balance1Before The balance of token1 of the router before execution
   * @param directionalPositionValue The directional position value before execution
   * @param direction The direction which the price changes
   * @param additionalData Additional data for the before execution
   */
  struct BeforeExecutionData {
    uint256 originalNftId;
    bytes32 poolUniqueId;
    uint256 amount0Before;
    uint256 amount1Before;
    uint256 balance0Before;
    uint256 balance1Before;
    uint256 directionalPositionValue;
    bool direction;
    bytes additionalData;
  }

  /**
   * @notice Data structure for pool and position info
   * @param poolUniqueId The unique ID of the pool
   * @param sqrtPriceX96 The sqrt price of the pool
   * @param tick The current tick of the pool
   * @param tickLower The lower tick of the position
   * @param tickUpper The upper tick of the position
   * @param token0 The token0 of the pool
   * @param token1 The token1 of the pool
   * @param amount0 The amount of token0 of the position
   * @param amount1 The amount of token1 of the position
   */
  struct PoolAndPositionInfo {
    bytes32 poolUniqueId;
    uint160 sqrtPriceX96;
    int24 tick;
    int24 tickLower;
    int24 tickUpper;
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
  }

  uint256 internal constant FEE_PRECISION = 1_000_000;

  mapping(bytes32 intentHash => uint256) public nftIds;

  modifier checkTokenLengths(ActionData calldata actionData) override {
    require(actionData.erc20Ids.length == 0, InvalidTokenData());
    require(actionData.erc721Ids.length == 1, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSmartIntentHook
  function beforeExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    ActionData calldata actionData
  )
    external
    view
    override
    checkTokenLengths(actionData)
    onlyWhitelistedRouter
    returns (uint256[] memory, bytes memory beforeExecutionData)
  {
    ZapMigrateHookData calldata hookIntentData = _decodeHookData(intentData.coreData.hookIntentData);

    uint256 currentNftId = nftIds[intentHash];
    if (currentNftId == 0) {
      currentNftId = hookIntentData.nftId;
    }

    PoolAndPositionInfo memory ppInfo =
      _getPoolAndPositionInfo(hookIntentData.nftAddress, currentNftId);

    uint256 valueInToken0 =
      ppInfo.amount0 + _convertToken1ToToken0(ppInfo.sqrtPriceX96, ppInfo.amount1);
    uint256 valueInToken1 =
      ppInfo.amount1 + _convertToken0ToToken1(ppInfo.sqrtPriceX96, ppInfo.amount0);

    uint256 directionalPositionValue;
    bool direction;
    if (ppInfo.tick - ppInfo.tickLower <= hookIntentData.maxDistanceFromLowerTickBeforeMigration) {
      direction = true;
      directionalPositionValue = valueInToken0;
    } else if (
      ppInfo.tickUpper - ppInfo.tick <= hookIntentData.maxDistanceFromUpperTickBeforeMigration
    ) {
      direction = false;
      directionalPositionValue = valueInToken1;
    } else {
      revert TooLargeDistanceFromTickBoundaries();
    }

    beforeExecutionData = abi.encode(
      BeforeExecutionData({
        originalNftId: currentNftId,
        poolUniqueId: ppInfo.poolUniqueId,
        amount0Before: ppInfo.amount0,
        amount1Before: ppInfo.amount1,
        balance0Before: ppInfo.token0.balanceOf(msg.sender),
        balance1Before: ppInfo.token1.balanceOf(msg.sender),
        directionalPositionValue: directionalPositionValue,
        direction: direction,
        additionalData: _getAdditionalData(hookIntentData.nftAddress)
      })
    );
  }

  /// @inheritdoc IKSSmartIntentHook
  function afterExecution(
    bytes32 intentHash,
    IntentData calldata intentData,
    bytes calldata _beforeExecutionData,
    bytes calldata
  )
    external
    override
    onlyWhitelistedRouter
    returns (
      address[] memory tokens,
      uint256[] memory fees,
      uint256[] memory amounts,
      address recipient
    )
  {
    if (_beforeExecutionData.length == 0) {
      return (new address[](0), new uint256[](0), new uint256[](0), address(0));
    }

    ZapMigrateHookData calldata hookIntentData = _decodeHookData(intentData.coreData.hookIntentData);
    BeforeExecutionData memory beforeExecutionData =
      abi.decode(_beforeExecutionData, (BeforeExecutionData));

    uint256 newNftId = _getNewNftId(hookIntentData.nftAddress, beforeExecutionData.additionalData);
    PoolAndPositionInfo memory ppInfo = _getPoolAndPositionInfo(hookIntentData.nftAddress, newNftId);
    if (ppInfo.poolUniqueId != beforeExecutionData.poolUniqueId) {
      revert InvalidPoolUniqueId();
    }

    // check owner
    if (
      IERC721(hookIntentData.nftAddress).ownerOf(beforeExecutionData.originalNftId)
        != intentData.coreData.mainAddress
    ) {
      revert InvalidOwner();
    }
    if (IERC721(hookIntentData.nftAddress).ownerOf(newNftId) != intentData.coreData.mainAddress) {
      revert InvalidOwner();
    }

    tokens = new address[](2);
    tokens[0] = ppInfo.token0;
    tokens[1] = ppInfo.token1;
    fees = new uint256[](2);
    fees[0] = ppInfo.token0.balanceOf(msg.sender) - beforeExecutionData.balance0Before;
    fees[1] = ppInfo.token1.balanceOf(msg.sender) - beforeExecutionData.balance1Before;
    amounts = new uint256[](2);

    // check max fees
    if (fees[0] * FEE_PRECISION > beforeExecutionData.amount0Before * hookIntentData.maxFees[0]) {
      revert ExceedMaxFeesPercent();
    }
    if (fees[1] * FEE_PRECISION > beforeExecutionData.amount1Before * hookIntentData.maxFees[1]) {
      revert ExceedMaxFeesPercent();
    }

    // check tick boundaries
    if (ppInfo.tick - ppInfo.tickLower < hookIntentData.minDistanceFromLowerTickAfterMigration) {
      revert TooSmallDistanceFromTickBoundaries();
    }
    if (ppInfo.tickUpper - ppInfo.tick < hookIntentData.minDistanceFromUpperTickAfterMigration) {
      revert TooSmallDistanceFromTickBoundaries();
    }
    if (ppInfo.tickUpper - ppInfo.tickLower < hookIntentData.minTickRangeLength) {
      revert TooSmallTickRangeLength();
    }
    if (ppInfo.tickUpper - ppInfo.tickLower > hookIntentData.maxTickRangeLength) {
      revert TooLargeTickRangeLength();
    }

    uint256 valueInToken0 =
      ppInfo.amount0 + _convertToken1ToToken0(ppInfo.sqrtPriceX96, ppInfo.amount1);
    if (valueInToken0 < hookIntentData.minValueInToken0) {
      revert InsufficientPositionValue();
    }
    uint256 valueInToken1 =
      ppInfo.amount1 + _convertToken0ToToken1(ppInfo.sqrtPriceX96, ppInfo.amount0);
    if (valueInToken1 < hookIntentData.minValueInToken1) {
      revert InsufficientPositionValue();
    }

    uint256 directionalPositionValueAfter =
      beforeExecutionData.direction ? valueInToken0 : valueInToken1;
    // check max value reduction per action
    if (
      directionalPositionValueAfter + hookIntentData.maxValueReductionPerAction
        < beforeExecutionData.directionalPositionValue
    ) {
      revert ExceedMaxValueReductionPerAction();
    }

    // record new NFT ID
    nftIds[intentHash] = newNftId;
  }

  function _decodeHookData(bytes calldata data)
    internal
    pure
    returns (ZapMigrateHookData calldata hookData)
  {
    assembly ('memory-safe') {
      hookData := add(data.offset, calldataload(data.offset))
    }
  }

  function _getPoolAndPositionInfo(address nftAddress, uint256 nftId)
    internal
    view
    virtual
    returns (PoolAndPositionInfo memory ppInfo);

  function _getAdditionalData(address nftAddress)
    internal
    view
    virtual
    returns (bytes memory additionalData)
  {}

  function _getNewNftId(address nftAddress, bytes memory additionalData)
    internal
    view
    virtual
    returns (uint256 newNftId);

  function _convertToken1ToToken0(uint256 sqrtPriceX96, uint256 amount1)
    internal
    pure
    virtual
    returns (uint256 amount0)
  {
    return amount1.mulDiv(FixedPoint96.Q96, sqrtPriceX96).mulDiv(FixedPoint96.Q96, sqrtPriceX96);
  }

  function _convertToken0ToToken1(uint256 sqrtPriceX96, uint256 amount0)
    internal
    pure
    virtual
    returns (uint256 amount1)
  {
    return amount0.mulDiv(sqrtPriceX96, FixedPoint96.Q96).mulDiv(sqrtPriceX96, FixedPoint96.Q96);
  }
}
