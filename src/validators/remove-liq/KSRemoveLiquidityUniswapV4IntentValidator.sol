// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity ^0.8.0;

// import 'src/validators/base/BaseIntentValidator.sol';

// import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

// import 'src/libraries/ConditionTreeLibrary.sol';
// import 'src/libraries/uniswapv4/StateLibrary.sol';
// import 'src/validators/base/BaseConditionalValidator.sol';

// contract KSRemoveLiquidityUniswapV4IntentValidator is
//   BaseIntentValidator,
//   BaseConditionalValidator
// {
//   using StateLibrary for IPoolManager;
//   using TokenHelper for address;

//   error InvalidOwner();
//   error InvalidLiquidity();
//   error InvalidOutputAmount();
//   error InvalidLength();

//   ConditionType public constant UNISWAPV4_YIELD_BASED =
//     ConditionType.wrap(keccak256('UNISWAPV4_YIELD_BASED'));

//   uint256 public constant PRECISION = 1_000_000;
//   uint256 public constant Q96 = 1 << 96;
//   address public immutable WETH;

//   /**
//    * @notice Local variables for remove liquidity validation
//    * @param recipient The recipient of the output tokens
//    * @param positionManager The position manager contract
//    * @param tokenId The token ID
//    * @param liquidity The liquidity to remove
//    * @param liquidityBefore The liquidity before removing liquidity
//    * @param sqrtPriceX96 The sqrt price X96 of the pool
//    * @param balancesBefore The token0, token1 balances before removing liquidity
//    * @param maxFees The max fee percents for each output token (1e6 = 100%)
//    * @param tokens The token0, token1 of the pool
//    * @param amounts The token amounts received from removing the specified liquidity (excluding unclaimed fees)
//    * @param unclaimedFees The unclaimed fees of the position
//    */
//   struct LocalVar {
//     address recipient;
//     IPositionManager positionManager;
//     uint256 tokenId;
//     uint256 liquidity;
//     uint256 liquidityBefore;
//     uint160 sqrtPriceX96;
//     uint256[2] balancesBefore;
//     uint256[2] maxFees;
//     address[2] tokens;
//     uint256[2] amounts;
//     uint256[2] unclaimedFees;
//   }

//   /**
//    * @notice Data structure for remove liquidity validation
//    * @param nftAddresses The NFT addresses
//    * @param nftIds The NFT IDs
//    * @param nodes The nodes of conditions (used to build the condition tree)
//    * @param maxFees The max fee percents for each output token (1e6 = 100%), [128 bits token0 max fee, 128 bits token1 max fee]
//    * @param wrapOrUnwrap wrap or unwrap token flag when remove liquidity from pool
//    * @param recipient The recipient
//    */
//   struct RemoveLiquidityValidationData {
//     address[] nftAddresses;
//     uint256[] nftIds;
//     Node[][] nodes;
//     uint256[] maxFees;
//     bool[] wrapOrUnwrap;
//     address recipient;
//   }

//   constructor(address _weth) {
//     WETH = _weth;
//   }

//   modifier checkTokenLengths(IKSSmartIntentRouter.TokenData calldata tokenData) override {
//     require(tokenData.erc20Data.length == 0, InvalidTokenData());
//     require(tokenData.erc721Data.length == 1, InvalidTokenData());
//     require(tokenData.erc1155Data.length == 0, InvalidTokenData());
//     _;
//   }

//   /// @inheritdoc IKSSmartIntentValidator
//   function validateBeforeExecution(
//     bytes32,
//     IKSSmartIntentRouter.IntentCoreData calldata coreData,
//     IKSSmartIntentRouter.ActionData calldata actionData
//   )
//     external
//     view
//     override
//     checkTokenLengths(actionData.tokenData)
//     returns (bytes memory beforeExecutionData)
//   {
//     // to avoid stack too deep
//     LocalVar memory localVar;

//     uint256 index;
//     uint256 fee0Generated;
//     uint256 fee1Generated;
//     (index, fee0Generated, fee1Generated, localVar.liquidity) =
//       _decodeValidatorData(actionData.validatorData);

//     Node[] calldata nodes = _cacheAndDecodeValidationData(coreData.validationData, localVar, index);

//     ConditionTree memory conditionTree =
//       _buildConditionTree(nodes, fee0Generated, fee1Generated, localVar.sqrtPriceX96);

//     this.validateConditionTree(conditionTree, 0);
//     (localVar.amounts[0], localVar.amounts[1], localVar.unclaimedFees[0], localVar.unclaimedFees[1])
//     = localVar.positionManager.poolManager().computePositionValues(
//       localVar.positionManager, localVar.tokenId, localVar.liquidity
//     );

//     return abi.encode(localVar);
//   }

//   /// @inheritdoc IKSSmartIntentValidator
//   function validateAfterExecution(
//     bytes32,
//     IKSSmartIntentRouter.IntentCoreData calldata coreData,
//     bytes calldata beforeExecutionData,
//     bytes calldata
//   ) external view override {
//     LocalVar calldata localVar = _decodeBeforeExecutionData(beforeExecutionData);

//     uint256 liquidityAfter = localVar.positionManager.getPositionLiquidity(localVar.tokenId);
//     require(liquidityAfter == localVar.liquidityBefore - localVar.liquidity, InvalidLiquidity());
//     require(
//       localVar.positionManager.ownerOf(localVar.tokenId) == coreData.mainAddress, InvalidOwner()
//     );

//     _validateOutput(localVar);
//   }

//   /// @inheritdoc IKSConditionalValidator
//   function evaluateCondition(Condition calldata condition, bytes calldata additionalData)
//     public
//     view
//     override
//     returns (bool isSatisfied)
//   {
//     if (condition.isType(UNISWAPV4_YIELD_BASED)) {
//       isSatisfied = _evaluateUniswapV4YieldCondition(condition, additionalData);
//     } else {
//       isSatisfied = super.evaluateCondition(condition, additionalData);
//     }
//   }

//   function _buildConditionTree(
//     Node[] calldata nodes,
//     uint256 fee0Collected,
//     uint256 fee1Collected,
//     uint160 sqrtPriceX96
//   ) internal pure returns (ConditionTree memory conditionTree) {
//     conditionTree.nodes = nodes;
//     conditionTree.additionalData = new bytes[](nodes.length);
//     for (uint256 i; i < nodes.length; ++i) {
//       if (!nodes[i].isLeaf() || nodes[i].condition.isType(TIME_BASED)) {
//         continue;
//       }
//       if (nodes[i].condition.isType(UNISWAPV4_YIELD_BASED)) {
//         conditionTree.additionalData[i] = abi.encode(fee0Collected, fee1Collected, sqrtPriceX96);
//       } else if (nodes[i].condition.isType(PRICE_BASED)) {
//         conditionTree.additionalData[i] = abi.encode(sqrtPriceX96);
//       }
//     }
//   }

//   function _validateOutput(LocalVar calldata localVar) internal view {
//     uint256 output0 = localVar.tokens[0].balanceOf(localVar.recipient) - localVar.balancesBefore[0];
//     uint256 output1 = localVar.tokens[1].balanceOf(localVar.recipient) - localVar.balancesBefore[1];

//     uint256 minOutput0 = (localVar.amounts[0] * (PRECISION - localVar.maxFees[0])) / PRECISION
//       + localVar.unclaimedFees[0];
//     uint256 minOutput1 = (localVar.amounts[1] * (PRECISION - localVar.maxFees[1])) / PRECISION
//       + localVar.unclaimedFees[1];

//     require(output0 >= minOutput0 && output1 >= minOutput1, InvalidOutputAmount());
//   }

//   function _cacheAndDecodeValidationData(
//     bytes calldata data,
//     LocalVar memory localVar,
//     uint256 index
//   ) internal view returns (Node[] calldata nodes) {
//     RemoveLiquidityValidationData calldata validationData = _decodeValidationData(data);
//     nodes = validationData.nodes[index];

//     localVar.recipient = validationData.recipient;
//     localVar.tokenId = validationData.nftIds[index];
//     localVar.positionManager = IPositionManager(validationData.nftAddresses[index]);
//     localVar.liquidityBefore = localVar.positionManager.getPositionLiquidity(localVar.tokenId);
//     localVar.maxFees =
//       [validationData.maxFees[index] >> 128, uint128(validationData.maxFees[index])];

//     {
//       IPoolManager poolManager = localVar.positionManager.poolManager();

//       (PoolKey memory poolKey,) = localVar.positionManager.getPoolAndPositionInfo(localVar.tokenId);
//       (localVar.sqrtPriceX96,,,) = poolManager.getSlot0(StateLibrary.getPoolId(poolKey));

//       localVar.tokens = [
//         poolKey.currency0 == address(0) ? TokenHelper.NATIVE_ADDRESS : poolKey.currency0,
//         poolKey.currency1 == address(0) ? TokenHelper.NATIVE_ADDRESS : poolKey.currency1
//       ];
//     }

//     if (validationData.wrapOrUnwrap[index]) {
//       localVar.tokens = [_adjustToken(localVar.tokens[0]), _adjustToken(localVar.tokens[1])];
//     }

//     localVar.balancesBefore = [
//       localVar.tokens[0].balanceOf(localVar.recipient),
//       localVar.tokens[1].balanceOf(localVar.recipient)
//     ];
//   }

//   function _decodeValidatorData(bytes calldata data)
//     internal
//     pure
//     returns (uint256 index, uint256 fee0Generated, uint256 fee1Generated, uint256 liquidity)
//   {
//     assembly ("memory-safe") {
//       index := calldataload(data.offset)
//       fee0Generated := calldataload(add(data.offset, 0x20))
//       fee1Generated := calldataload(add(data.offset, 0x40))
//       liquidity := calldataload(add(data.offset, 0x60))
//     }
//   }

//   function _decodeBeforeExecutionData(bytes calldata data)
//     internal
//     pure
//     returns (LocalVar calldata localVar)
//   {
//     assembly ("memory-safe") {
//       localVar := data.offset
//     }
//   }

//   function _decodeValidationData(bytes calldata data)
//     internal
//     pure
//     returns (RemoveLiquidityValidationData calldata validationData)
//   {
//     assembly ("memory-safe") {
//       validationData := add(data.offset, calldataload(data.offset))
//     }
//   }

//   /**
//    * @notice helper function to evaluate whether the yield condition is satisfied
//    * @dev Calculates yield as: (fees_in_token0_terms) / (initial_amounts_in_token0_terms)
//    * @param condition The yield condition containing target yield and initial amounts
//    * @param additionalData Encoded fee0, fee1, and sqrtPriceX96 values
//    * @return true if actual yield >= target yield, false otherwise
//    */
//   function _evaluateUniswapV4YieldCondition(
//     Condition calldata condition,
//     bytes calldata additionalData
//   ) internal pure returns (bool) {
//     uint256 fee0;
//     uint256 fee1;
//     uint160 sqrtPriceX96;

//     assembly ("memory-safe") {
//       fee0 := calldataload(additionalData.offset)
//       fee1 := calldataload(add(additionalData.offset, 0x20))
//       sqrtPriceX96 := calldataload(add(additionalData.offset, 0x40))
//     }

//     YieldCondition calldata yieldCondition = _decodeYieldCondition(condition.data);

//     uint256 initialAmount0 = yieldCondition.initialAmounts >> 128;
//     uint256 initialAmount1 = uint256(uint128(yieldCondition.initialAmounts));

//     uint256 numerator = fee0 + _convertToken1ToToken0(sqrtPriceX96, fee1);
//     uint256 denominator = initialAmount0 + _convertToken1ToToken0(sqrtPriceX96, initialAmount1);
//     if (denominator == 0) return false;

//     uint256 yield = (numerator * PRECISION) / denominator;

//     return yield >= yieldCondition.targetYield;
//   }

//   /**
//    * @notice Converts token1 amount to equivalent token0 amount using current price
//    * @dev formula: amount0 = amount1 * Q192 / sqrtPriceX96^2
//    * @param sqrtPriceX96 The pool's sqrt price
//    * @param amount1 Amount of token1 to convert
//    * @return amount0 Equivalent amount in token0 terms
//    */
//   function _convertToken1ToToken0(uint160 sqrtPriceX96, uint256 amount1)
//     internal
//     pure
//     returns (uint256 amount0)
//   {
//     amount0 = Math.mulDiv(Math.mulDiv(amount1, Q96, sqrtPriceX96), Q96, sqrtPriceX96);
//   }

//   function _adjustToken(address token) internal view returns (address adjustedToken) {
//     if (token != WETH && token != TokenHelper.NATIVE_ADDRESS) {
//       return token;
//     }

//     return token == WETH ? TokenHelper.NATIVE_ADDRESS : WETH;
//   }
// }
