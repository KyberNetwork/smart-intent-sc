// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './base/BaseIntentValidator.sol';
import 'openzeppelin-contracts/token/ERC20/IERC20.sol';
import 'src/interfaces/uniswapv4/IPositionManager.sol';
import 'src/libraries/StateLibrary.sol';
import 'src/libraries/TokenLibrary.sol';

contract KSZapOutUniswapV4IntentValidator is BaseIntentValidator {
  using StateLibrary for IPoolManager;
  using TokenLibrary for address;

  error InvalidZapOutPosition();

  error OutsidePriceRange(uint160 sqrtPLower, uint160 sqrtPUpper, uint160 sqrtPriceX96);

  error InvalidOwner();

  error GetPositionLiquidityFailed();

  error GetSqrtPriceX96Failed();

  error BelowMinRate(uint256 liquidity, uint256 minRate, uint256 outputAmount);

  uint256 public constant RATE_DENOMINATOR = 1e18;

  struct ZapOutUniswapV4ValidationData {
    address[] nftAddresses;
    uint256[] nftIds;
    address[] pools;
    address[] outputTokens;
    uint160[] sqrtPLowers;
    uint160[] sqrtPUppers;
    uint256[] minRates;
    address recipient;
  }

  modifier checkTokenLengths(IKSSessionIntentRouter.TokenData calldata tokenData) override {
    require(tokenData.erc20Data.length == 0, InvalidTokenData());
    require(tokenData.erc721Data.length == 1, InvalidTokenData());
    require(tokenData.erc1155Data.length == 0, InvalidTokenData());
    _;
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateBeforeExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    IKSSessionIntentRouter.ActionData calldata actionData
  )
    external
    view
    override
    checkTokenLengths(actionData.tokenData)
    returns (bytes memory beforeExecutionData)
  {
    uint256 index = abi.decode(actionData.validatorData, (uint256));

    ZapOutUniswapV4ValidationData memory validationData =
      abi.decode(coreData.validationData, (ZapOutUniswapV4ValidationData));

    IPositionManager positionManager = IPositionManager(validationData.nftAddresses[index]);
    uint256 tokenId = validationData.nftIds[index];
    address outputToken = validationData.outputTokens[index];

    IKSSessionIntentRouter.ERC721Data[] calldata erc721Data = actionData.tokenData.erc721Data;
    require(erc721Data[0].token == address(positionManager), InvalidTokenData());
    require(erc721Data[0].tokenId == tokenId, InvalidTokenData());

    bytes32 poolId;
    {
      (PoolKey memory poolKey,) = positionManager.getPoolAndPositionInfo(tokenId);
      poolId = _getPoolId(poolKey);
    }

    (uint160 sqrtPriceX96,,,) = positionManager.poolManager().getSlot0(poolId);
    require(
      sqrtPriceX96 >= validationData.sqrtPLowers[index]
        && sqrtPriceX96 <= validationData.sqrtPUppers[index],
      OutsidePriceRange(
        validationData.sqrtPLowers[index], validationData.sqrtPUppers[index], sqrtPriceX96
      )
    );

    uint256 liquidityBefore = positionManager.getPositionLiquidity(tokenId);
    uint256 tokenBalanceBefore = outputToken.balanceOf(validationData.recipient);

    return abi.encode(
      positionManager,
      tokenId,
      outputToken,
      liquidityBefore,
      tokenBalanceBefore,
      validationData.minRates[index],
      validationData.recipient
    );
  }

  /// @inheritdoc IKSSessionIntentValidator
  function validateAfterExecution(
    bytes32,
    IKSSessionIntentRouter.IntentCoreData calldata coreData,
    bytes calldata beforeExecutionData,
    bytes calldata
  ) external view override {
    uint256 minRate;
    uint256 liquidity;
    uint256 outputAmount;

    {
      IPositionManager positionManager;
      uint256 tokenId;
      address outputToken;
      uint256 liquidityBefore;
      uint256 tokenBalanceBefore;
      address recipient;

      (
        positionManager,
        tokenId,
        outputToken,
        liquidityBefore,
        tokenBalanceBefore,
        minRate,
        recipient
      ) = abi.decode(
        beforeExecutionData,
        (IPositionManager, uint256, address, uint256, uint256, uint256, address)
      );

      uint256 liquidityAfter = positionManager.getPositionLiquidity(tokenId);
      require(
        liquidityAfter == 0 || positionManager.ownerOf(tokenId) == coreData.mainAddress,
        InvalidOwner()
      );
      liquidity = liquidityBefore - liquidityAfter;

      outputAmount = outputToken.balanceOf(recipient) - tokenBalanceBefore;
    }

    if (outputAmount * RATE_DENOMINATOR < minRate * liquidity) {
      revert BelowMinRate(liquidity, minRate, outputAmount);
    }
  }

  function _getPoolId(PoolKey memory poolKey) internal pure returns (bytes32 poolId) {
    assembly {
      poolId := keccak256(poolKey, 0xa0)
    }
  }
}
